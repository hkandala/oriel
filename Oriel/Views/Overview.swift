#if os(macOS)
    import AppKit
    import HerdrKit
    import SwiftUI

    /// Every tab of the window's sessions as live miniatures of their pages (D70): a page per session, paged
    /// sideways; its workspaces scrolled vertically. A click, Esc or the toggle zooms the selected tab's miniature to
    /// the strip's page, then the strip shows.
    struct Overview: View {
        let pages: WindowPages
        /// Where the strip starts when the overview closes: the sidebar's width, or 0.
        let leading: CGFloat
        @State private var position = ScrollPosition(idType: String.self)
        /// Each tile's miniature, in the overview: not observed, so a scroll redraws nothing.
        @State private var frames = Frames()
        /// The tab whose miniature grows to the page, from its tile's frame; `grown` once it moves.
        @State private var zoom: Zoom?
        @State private var grown = false
        @State private var monitor: Any?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        final class Frames {
            var rects: [String: CGRect] = [:]
        }

        private struct Zoom {
            let page: Page
            let tab: HostStore.Tab
            let from: CGRect
        }

        var body: some View {
            GeometryReader { proxy in
                // The strip's page, as `Strip` lays it out beside the sidebar.
                let strip = CGRect(x: leading + gap, y: 4, width: max(proxy.size.width - leading - 2 * gap, 1),
                                   height: max(proxy.size.height - 4 - gap, 1))
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.list) { page in
                            OverviewPage(
                                pages: pages,
                                page: page,
                                size: strip.size,
                                frames: frames,
                                columns: min(4, max(2, Int((proxy.size.width - 32) / 356))),
                                zooming: page === zoom?.page ? zoom?.tab.id : nil,
                            ) {
                                open(page, $0, $1)
                            }
                            .containerRelativeFrame([.horizontal, .vertical])
                            .accessibilityHidden(page !== pages.current)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition($position)
                .scrollIndicators(.never)
                .opacity(grown ? 0 : 1)
                // Nothing under the zoom takes a click.
                .allowsHitTesting(zoom == nil)
                .onScrollPhaseChange { _, phase in
                    if phase == .idle, let id = position.viewID(type: String.self), id != pages.current?.id,
                       let page = pages.list.first(where: { $0.id == id })
                    {
                        pages.show(page)
                    }
                }
                .onChange(of: pages.current?.id, initial: true) { old, new in
                    guard let new, position.viewID(type: String.self) != new else { return }
                    withAnimation(old == nil || reduceMotion && !Animation.forceMotion ? nil : .session()) {
                        position.scrollTo(id: new)
                    }
                    // The first layout of the lazy stack can miss it.
                    if old == nil {
                        Task { position.scrollTo(id: new) }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let zoom {
                        Miniature(tab: zoom.tab, page: zoom.page, size: strip.size)
                            .modifier(Grow(progress: grown ? 1 : 0, from: zoom.from, page: strip))
                    }
                }
                .onChange(of: pages.leaving) {
                    if pages.leaving, zoom == nil {
                        leave()
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
            // The keyboard leaves the terminals, which take none while in a miniature (`PaneSurfaceView`). Esc by a
            // monitor: a SwiftUI focus did not take the keyboard from a terminal moving into a miniature (CI).
            .onAppear {
                pages.window?.makeFirstResponder(nil)
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 53 else { return event }
                    let leave = MainActor.assumeIsolated {
                        // Not a panel's (the palette's, the shortcuts').
                        guard let window = pages.window, NSApp.keyWindow === window, !pages.panelOpen,
                              !(window.firstResponder is NSText) else { return false }
                        pages.leaving = true
                        return true
                    }
                    return leave ? nil : event
                }
            }
            .onDisappear {
                monitor.map(NSEvent.removeMonitor)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("overview")
        }

        static let space = "overview"

        private func open(_ page: Page, _ workspace: HostStore.Workspace, _ tab: HostStore.Tab) {
            page.select(workspace, tab: tab.id)
            pages.leaving = true
        }

        /// The selected tab's miniature grows to the strip's page (its terminals scale up live), then the strip shows.
        /// At once under Reduce Motion, or when its tile is not laid out.
        private func leave() {
            guard let page = pages.current, let tab = page.selectedTab, let from = frames.rects["\(page.id) \(tab.id)"],
                  !reduceMotion || Animation.forceMotion
            else { return pages.closeOverview() }
            zoom = Zoom(page: page, tab: tab, from: from)
            // Next turn: a view inserted in the same update as the change starts at its end, with no motion.
            Task {
                withAnimation(.easeOut(duration: 0.25)) { grown = true } completion: {
                    pages.closeOverview()
                }
            }
        }
    }

    /// The zoom's frame at each step: a plain animated frame reached the miniature's terminal views only at its end
    /// (their sizes come from a `GeometryReader`, which a layout animation gives the final size at once).
    private struct Grow: ViewModifier, Animatable {
        var progress: CGFloat
        let from: CGRect
        let page: CGRect

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let step = { (start: CGFloat, end: CGFloat) in start + (end - start) * progress }
            let rect = CGRect(x: step(from.minX, page.minX), y: step(from.minY, page.minY),
                              width: step(from.width, page.width), height: step(from.height, page.height))
            content.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }
    }

    extension WindowPages {
        /// Opens the overview, or leaves it by its zoom.
        func toggleOverview() {
            if overview {
                leaving = true
            } else {
                overview = true
                showTerminals()
            }
        }

        /// Runs `action` now, or after the overview's zoom when it is open: an action that opens the sidebar would
        /// move the zoom's target and resize the tiles' terminals.
        func afterOverview(_ action: @escaping () -> Void) {
            if overview {
                afterOverview = action
                leaving = true
            } else {
                action()
            }
        }

        /// The strip shows again, and the keyboard goes back to the tab's card.
        func closeOverview() {
            overview = false
            leaving = false
            overviewTabs = [:]
            showTerminals()
            current?.focusKeyboardCard()
            afterOverview?()
            afterOverview = nil
        }
    }

    extension Page {
        /// The cards' terminals of these tabs (terminal id → pane id), floated ones aside.
        func cardTerminals(_ tabIDs: Set<String>) -> [String: String] {
            Dictionary(store.panes.compactMap { pane in
                tabIDs.contains(pane.tabID) && !floats(pane) ? pane.terminalID.map { ($0, pane.id) } : nil
            }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// One session: its workspaces in the sidebar's order, each its name over a grid of its tabs.
    private struct OverviewPage: View {
        let pages: WindowPages
        let page: Page
        /// The strip's page.
        let size: CGSize
        let frames: Overview.Frames
        /// Tiles a row: 2 to 4 by the window's width.
        let columns: Int
        /// The tab whose miniature zooms: its tile leaves the terminals to it.
        let zooming: String?
        let open: (HostStore.Workspace, HostStore.Tab) -> Void

        var body: some View {
            let grid = Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 32) {
                    Text(page.store.title).font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("overview.title")
                    ForEach(page.sidebarWorkspaces) { workspace in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(workspace.label).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("overview.workspace.\(workspace.id)")
                            LazyVGrid(columns: grid, spacing: 16) {
                                ForEach(workspace.tabs) { tab in
                                    Tile(
                                        pages: pages,
                                        page: page,
                                        workspace: workspace,
                                        tab: tab,
                                        size: size,
                                        frames: frames,
                                        zooming: zooming == tab.id,
                                    ) { open(workspace, tab) }
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(workspace.label)
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.never)
            .accessibilityIdentifier("overview.page.\(page.id)")
        }
    }

    /// A tab as one card: its title row (icon stack, title, status; × on hover) over the miniature of its page. The
    /// selected tab of its workspace has the keyboard card's look.
    private struct Tile: View {
        let pages: WindowPages
        let page: Page
        let workspace: HostStore.Workspace
        let tab: HostStore.Tab
        /// The strip's page.
        let size: CGSize
        let frames: Overview.Frames
        /// Its miniature zooms to the page: the tile leaves the terminals to it.
        let zooming: Bool
        let open: () -> Void
        @State private var hovering = false

        var body: some View {
            let selected = page.selectedTabIDs[workspace.id] == tab.id
            let state = page.store.strongest([tab.id])?.state
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    IconStack(panes: page.stack(tab), badge: state)
                    FadeText(text: page.titleLabel(tab)).fontWeight(.medium)
                    Spacer(minLength: 0)
                    if hovering {
                        // As the tab bar's ×: asks first only when a program runs.
                        IconButton(symbol: "xmark", help: "Close Tab", key: .closeTab, size: 22) {
                            page.close(.tab(tab.id))
                        }
                        .accessibilityIdentifier("overview.tab.\(tab.id).close")
                    } else if let state, state != .idle {
                        StateCapsule(state: state)
                    }
                }
                .padding(.leading, 11)
                .padding(.trailing, 8)
                .frame(height: PaneCard.header)
                Group {
                    if zooming {
                        Color.clear
                    } else {
                        Miniature(tab: tab, page: page, size: size)
                    }
                }
                .aspectRatio(size, contentMode: .fit)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Overview.space)) } action: {
                    frames.rects["\(page.id) \(tab.id)"] = $0
                }
                .padding([.horizontal, .bottom], gap)
            }
            .background(CardSurface(keyboard: selected))
            // Only the tiles the lazy grid lays out stream: the cost follows the tiles in view, not the session (a
            // card at full window costs 52 MB on Retina).
            .onAppear { laidOut(true) }
            .onDisappear {
                // Scrolled away: Esc leaves at once, not from where it was.
                frames.rects["\(page.id) \(tab.id)"] = nil
                laidOut(false)
            }
            .contentShape(.rect)
            .onTapGesture(perform: open)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(page.titleText(tab))
            .accessibilityValue(selected ? "selected" : "")
            .accessibilityIdentifier("overview.tab.\(tab.id)")
            .accessibilityAction(.default, open)
        }

        private func laidOut(_ shown: Bool) {
            // Closing: `closeOverview` let them all go at once.
            guard pages.overview else { return }
            if shown {
                pages.overviewTabs[page.id, default: []].insert(tab.id)
            } else {
                pages.overviewTabs[page.id]?.remove(tab.id)
            }
            pages.showTerminals()
        }
    }
#endif
