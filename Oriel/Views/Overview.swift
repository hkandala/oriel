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
        /// Fades in once open (phase 29).
        @State private var opened = false
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
                // Wide margins round the grid, as in the user's reference.
                let side = max(48, proxy.size.width * 0.08)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.list) { page in
                            OverviewPage(
                                pages: pages,
                                page: page,
                                size: strip.size,
                                frames: frames,
                                side: side,
                                columns: min(4, max(2, Int((proxy.size.width - 2 * side + 16) / 356))),
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
                    // The first layout can miss it.
                    if old == nil {
                        Task { position.scrollTo(id: new) }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let zoom {
                        Miniature(tab: zoom.tab, page: zoom.page, size: strip.size, live: pages.overviewLive)
                            .modifier(Grow(progress: grown ? 1 : 0, from: zoom.from, page: strip))
                    }
                }
                .onChange(of: pages.leaving) {
                    if pages.leaving, zoom == nil {
                        leave(in: CGRect(origin: .zero, size: proxy.size))
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
            .opacity(opened ? 1 : 0)
            // e2e: the live cards and the snapshots kept (`-recordMotion YES`).
            .testValue("overview.snapshots", "Overview Snapshots",
                       "\(pages.overviewLive.count) \(PaneTerminal.snapshots.count)", shown: TerminalHost.Host.record)
            .testValue(
                "overview.motion",
                "Overview Motion",
                "\(MiniTerminal.Mini.most)",
                shown: TerminalHost.Host.record,
            )
            // The keyboard leaves the terminals, which take none while in a miniature (`PaneSurfaceView`). Esc by a
            // monitor: a SwiftUI focus did not take the keyboard from a terminal moving into a miniature (CI).
            .onAppear {
                withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.18)) { opened = true }
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
        /// At once under Reduce Motion, or when its tile is scrolled out of view.
        private func leave(in view: CGRect) {
            guard let page = pages.current, let tab = page.selectedTab, let from = frames.rects["\(page.id) \(tab.id)"],
                  from.intersects(view), !reduceMotion || Animation.forceMotion
            else { return pages.closeOverview() }
            zoom = Zoom(page: page, tab: tab, from: from)
            // Next turn: a view inserted in the same update as the change starts at its end, with no motion.
            Task {
                withAnimation(.easeOut(duration: 0.18)) { grown = true } completion: {
                    pages.closeOverview()
                }
            }
        }
    }

    extension View {
        /// The window's chrome (the sidebar, the title row) under the overview: laid out while it is open, hidden, so
        /// it fades in with the zoom; made once the zoom ended, it came a moment late in a big session (phase 30).
        /// `own`: the overview's ×, the other way round.
        func underOverview(_ pages: WindowPages, own: Bool = false) -> some View {
            modifier(UnderOverview(pages: pages, own: own))
        }
    }

    private struct UnderOverview: ViewModifier {
        let pages: WindowPages
        let own: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            let open = pages.overview && !pages.leaving
            content.opacity(open == own ? 1 : 0)
                // The zoom's time.
                .animation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.18), value: open)
                .allowsHitTesting(open == own)
                // Not `accessibilityHidden(false)`, which overrides the hidden ones inside (a button's overlay image
                // took its identifier too).
                .accessibilityElement(children: open == own ? .contain : .ignore)
                // Out of the key view loop too: Tab would reach a hidden field.
                .disabled(open != own)
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
            overviewSettling?.cancel()
            showTerminals()
            current?.focusKeyboardCard()
            afterOverview?()
            afterOverview = nil
        }
    }

    extension WindowPages {
        /// The cards of the overview's tiles in view, whole tabs, the latest in first, up to a cap: each live one
        /// costs a surface at its card's size (about 52 MB at full window on Retina), so the cost follows the cap, not
        /// the session. A remote machine's cards share the relay's one SSH session: 6. The other tiles show their
        /// snapshot.
        func overviewCards(_ page: Page) -> [String: String] {
            let tabs = (overviewTabs[page.id] ?? []).reversed().map { tileCards(page, $0) }
            // Those with a card that has no picture yet first (a loader shows there), so each tile in view gets one in
            // turn (phase 30); one that drew lets go if another waits, and keeps its snapshot. Then the live ones, so
            // the last turn does not start another.
            let drawn = { (tab: [(String, String)]) in self.pictured(page, tab) }
            let live = { (tab: [(String, String)]) in tab.allSatisfy { self.overviewLive.contains($0.0) } }
            var cards: [String: String] = [:]
            let waiting = tabs.filter { !drawn($0) }, shown = tabs.filter { drawn($0) && live($0) }
            for tabCards in waiting + shown + tabs.filter({ drawn($0) && !live($0) }) {
                // A tab over the cap alone still loads.
                guard cards.isEmpty || cards.count + tabCards.count <= (machine.isRemote ? 6 : 16) else { continue }
                cards.merge(tabCards) { first, _ in first }
            }
            return cards
        }

        /// A tab's cards in its tile (terminal id, pane id), as its miniature draws them: its zoomed card alone, no
        /// floated one.
        func tileCards(_ page: Page, _ tab: String) -> [(String, String)] {
            let panes = (page.store.tabPanes[tab] ?? []).filter { !page.floats($0) }
            let zoomed = panes.filter { $0.id == page.zoomedPaneID }
            return (zoomed.isEmpty ? panes : zoomed).compactMap { pane in pane.terminalID.map { ($0, pane.id) } }
        }

        /// Each of these cards has a picture for its tile.
        func pictured(_ page: Page, _ cards: [(String, String)]) -> Bool {
            cards.allSatisfy { id, _ in page.terminals.terminals([id]).first?.pictured == true }
        }

        /// The tiles in view turn live 150 ms after the last change: while tiles keep coming (a scroll), none does (a
        /// new surface and stream each, on the main thread); they show their snapshots meanwhile. A tile scrolled away
        /// lets go then too, and one that drew while another waits (`overviewCards`).
        func settleOverview() {
            guard overview, !leaving else { return }
            overviewSettling?.cancel()
            overviewSettling = Task {
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled {
                    showTerminals()
                }
            }
        }
    }
#endif
