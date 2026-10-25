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
        @State private var zoom: (tab: HostStore.Tab, from: CGRect)?
        @State private var grown = false
        @FocusState private var focused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        final class Frames {
            var rects: [String: CGRect] = [:]
        }

        var body: some View {
            GeometryReader { proxy in
                // The strip's page, as `Strip` lays it out beside the sidebar.
                let strip = CGRect(x: leading + gap, y: 4, width: max(proxy.size.width - leading - 2 * gap, 1),
                                   height: max(proxy.size.height - 4 - gap, 1))
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.list) { page in
                            OverviewPage(page: page, size: strip.size, frames: frames, zooming: zoom?.tab.id) {
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
                .onScrollPhaseChange { _, phase in
                    if phase == .idle, let id = position.viewID(type: String.self), id != pages.current?.id,
                       let page = pages.list.first(where: { $0.id == id })
                    {
                        pages.show(page)
                    }
                }
                .onChange(of: pages.current?.id, initial: true) { old, new in
                    guard let new, position.viewID(type: String.self) != new else { return }
                    withAnimation(old == nil || reduceMotion && !Animation.forceMotion ? nil : .session) {
                        position.scrollTo(id: new)
                    }
                    Task { position.scrollTo(id: new) }
                }
                .overlay(alignment: .topLeading) {
                    if let zoom, let page = pages.current {
                        let rect = grown ? strip : zoom.from
                        Miniature(tab: zoom.tab, page: page, size: strip.size)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .onChange(of: pages.leaving) {
                    if pages.leaving, zoom == nil {
                        leave(strip: strip)
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.escape) {
                pages.leaving = true
                return .handled
            }
            // The keyboard leaves the terminals, which take none while in a miniature (`PaneSurfaceView`).
            .onAppear { focused = true }
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
        private func leave(strip _: CGRect) {
            guard let page = pages.current, let tab = page.selectedTab, let from = frames.rects[tab.id],
                  !reduceMotion || Animation.forceMotion
            else { return pages.closeOverview() }
            zoom = (tab, from)
            withAnimation(.easeOut(duration: 0.25)) { grown = true } completion: {
                pages.closeOverview()
            }
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

        /// The strip shows again, and the keyboard goes back to the tab's card.
        func closeOverview() {
            overview = false
            leaving = false
            showTerminals()
            current?.focusKeyboardCard()
        }
    }

    extension Page {
        /// Every card's terminal of the session (terminal id → pane id), floated ones aside: the overview's.
        var cardTerminals: [String: String] {
            Dictionary(store.panes.compactMap { pane in floats(pane) ? nil : pane.terminalID.map { ($0, pane.id) } },
                       uniquingKeysWith: { first, _ in first })
        }
    }

    /// One session: its workspaces in the sidebar's order, each its name over a grid of its tabs.
    private struct OverviewPage: View {
        let page: Page
        /// The strip's page.
        let size: CGSize
        let frames: Overview.Frames
        /// The tab whose miniature zooms: its tile leaves the terminals to it.
        let zooming: String?
        let open: (HostStore.Workspace, HostStore.Tab) -> Void

        var body: some View {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 32) {
                    Text(page.id).font(.system(size: 13, weight: .semibold))
                    ForEach(page.sidebarWorkspaces) { workspace in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(workspace.label).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("overview.workspace.\(workspace.id)")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                                ForEach(workspace.tabs) { tab in
                                    tile(workspace, tab)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.never)
            .accessibilityIdentifier("overview.page.\(page.id)")
        }

        private func tile(_ workspace: HostStore.Workspace, _ tab: HostStore.Tab) -> some View {
            let selected = page.selectedTabIDs[workspace.id] == tab.id
            let state = page.store.strongest([tab.id])?.state
            return Button { open(workspace, tab) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        IconStack(panes: page.stack(tab), badge: state)
                        FadeText(text: page.titleLabel(tab)).fontWeight(.medium)
                        Spacer(minLength: 0)
                        if let state, state != .idle {
                            StateCapsule(state: state)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Pill(shape: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    Group {
                        if zooming == tab.id {
                            Color.clear
                        } else {
                            Miniature(tab: tab, page: page, size: size)
                        }
                    }
                    .aspectRatio(size, contentMode: .fit)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Overview.space)) } action: {
                        frames.rects[tab.id] = $0
                    }
                }
                .padding(6)
            }
            .buttonStyle(ChromeStyle(radius: 12))
            .accessibilityLabel(page.titleText(tab))
            .accessibilityValue(selected ? "selected" : "")
            .accessibilityIdentifier("overview.tab.\(tab.id)")
        }
    }

    /// A tab's page at the size it is given: its cards in herdr's layout (or its zoomed card), each with its terminal
    /// live at its place in the card, scaled from the strip's page (`size`).
    struct Miniature: View {
        let tab: HostStore.Tab
        let page: Page
        let size: CGSize

        var body: some View {
            GeometryReader { proxy in
                let scale = proxy.size.width / size.width, area = CGRect(origin: .zero, size: size)
                if let tree = tab.tree {
                    let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                    let cards = Parts(tree, in: area, held: [:]).cards.filter { zoomed == nil || $0.id == zoomed }
                    ZStack(alignment: .topLeading) {
                        ForEach(cards, id: \.id) { card in
                            let rect = zoomed == nil ? card.rect : area
                            MiniCard(id: card.id, page: page, size: rect.size, scale: scale)
                                .frame(width: rect.width * scale, height: rect.height * scale)
                                .position(x: rect.midX * scale, y: rect.midY * scale)
                        }
                    }
                }
            }
        }
    }

    /// A card at `scale`: its fill and edge, and its terminal where the page's card has it (under the header, 10 pt
    /// in, 8 pt up from the bottom). A floated pane's shows the float icon.
    private struct MiniCard: View {
        let id: String
        let page: Page
        /// The card in the strip's page.
        let size: CGSize
        let scale: CGFloat
        @Environment(\.look) private var look

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10 * scale, style: .continuous),
                edge = look.edge(keyboard: false)
            let pane = page.store.pane(id)
            let terminal = CGSize(width: max(size.width - 2 * PaneCard.inset, 1),
                                  height: max(size.height - PaneCard.header - gap, 1))
            shape.fill(look.cardFill)
                .overlay(shape.stroke(edge.color, lineWidth: edge.width))
                .overlay(alignment: .topLeading) {
                    if let pane, page.floats(pane) {
                        Image(systemName: "pip").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let view = pane.flatMap(page.terminal) {
                        MiniTerminal(terminal: view, size: terminal)
                            .frame(width: terminal.width * scale, height: terminal.height * scale)
                            .padding(.leading, PaneCard.inset * scale)
                            .padding(.top, PaneCard.header * scale)
                    }
                }
        }
    }

    /// The pane's own terminal view, drawn at the miniature's size: its bounds are the card's terminal size, so
    /// AppKit scales the layer and libghostty keeps its grid (herdr's PTY never resizes). Clicks and scrolls go to
    /// the tile. The newest host adopts the view, as `TerminalHost`'s do.
    struct MiniTerminal: NSViewRepresentable {
        let terminal: PaneTerminal
        let size: CGSize

        func makeNSView(context _: Context) -> Mini {
            let mini = Mini()
            mini.size = size
            mini.wantsLayer = true
            mini.clipsToBounds = true
            mini.addSubview(terminal.view)
            return mini
        }

        func updateNSView(_ mini: Mini, context _: Context) {
            mini.size = size
            mini.fit()
        }

        final class Mini: NSView {
            var size = CGSize.zero

            override var isFlipped: Bool {
                true
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }

            override func setFrameSize(_ newSize: NSSize) {
                super.setFrameSize(newSize)
                fit()
            }

            func fit() {
                guard !frame.isEmpty, size.width > 0, size.height > 0 else { return }
                setBoundsSize(size)
                guard let view = subviews.first as? PaneSurfaceView, view.frame.size != size else { return }
                // Before libghostty hears of the size, as the card's host does.
                view.terminal?.hold()
                view.frame = CGRect(origin: .zero, size: size)
            }
        }
    }
#endif
