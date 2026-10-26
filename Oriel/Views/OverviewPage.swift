#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// One session: its workspaces in the sidebar's order, each its name over a grid of its tabs.
    struct OverviewPage: View {
        let pages: WindowPages
        let page: Page
        /// The strip's page.
        let size: CGSize
        let frames: Overview.Frames
        /// The margin left and right; the grid between them.
        let side: CGFloat
        /// Tiles a row: 2 to 4 by the window's width.
        let columns: Int
        /// The tab whose miniature zooms: its tile leaves the terminals to it.
        let zooming: String?
        let open: (HostStore.Workspace, HostStore.Tab) -> Void
        @State private var scrolling = false

        var body: some View {
            ScrollView(.vertical) {
                // Lazy by row: only the tiles in or near view are made, whatever the session's size. Fixed columns:
                // a short last row keeps their width.
                let grid = Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
                VStack(alignment: .leading, spacing: 16) {
                    Text(page.store.title).font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("overview.title")
                    LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                        ForEach(page.sidebarWorkspaces) { workspace in
                            Section {
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
                            } header: {
                                // 32 pt below the rows above, 12 pt above its own.
                                Text(workspace.label).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 16)
                                    .padding(.bottom, -4)
                                    .accessibilityIdentifier("overview.workspace.\(workspace.id)")
                            }
                        }
                    }
                }
                .padding(.horizontal, side)
                .padding(.vertical, 40)
                // No hover or hit tests in the tiles while it scrolls: SwiftUI looked for the tile under the pointer
                // at every frame (a tenth of the main thread, phase 30).
                .allowsHitTesting(!scrolling)
            }
            .scrollIndicators(.never)
            .onScrollPhaseChange { _, phase in
                scrolling = phase.isScrolling
                pages.overviewScrolling = phase != .idle
                if phase == .idle {
                    pages.settleOverview()
                }
            }
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
            let state = tab.agent?.state
            let loading = !zooming && !pages.pictured(page, pages.tileCards(page, tab.id))
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
                        Miniature(tab: tab, page: page, size: size, live: pages.overviewLive)
                    }
                }
                // A card with no picture yet (never drawn, or its snapshot gone): it loads in turn (`overviewCards`).
                .overlay {
                    if loading {
                        Waiting().accessibilityIdentifier("overview.tab.\(tab.id).loading")
                            // e2e (`-recordLatency`): it showed, however briefly.
                            .onAppear { Latency.shared.note("loader \(tab.id)") }
                    }
                }
                // It drew: a tile waiting loads.
                .onChange(of: loading) { pages.settleOverview() }
                .aspectRatio(size, contentMode: .fit)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Overview.space)) } action: {
                    frames.rects["\(page.id) \(tab.id)"] = $0
                    pages.tileScale = $0.width / size.width
                }
                .padding([.horizontal, .bottom], gap)
            }
            .frame(maxWidth: .infinity)
            .background(CardSurface(keyboard: selected))
            // The tiles in view may be live (`showTerminals`); the others show their snapshot.
            .onScrollVisibilityChange(threshold: 0.01) { laidOut($0) }
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
            // Closing: `closeOverview` lets them all go at once.
            guard pages.overview else { return }
            // The latest in view last: they go live first.
            pages.overviewTabs[page.id, default: []].removeAll { $0 == tab.id }
            if shown {
                pages.overviewTabs[page.id, default: []].append(tab.id)
            }
            pages.settleOverview()
        }
    }
#endif
