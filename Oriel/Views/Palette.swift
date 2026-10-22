#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// ⌘K: a floating glass panel to jump to a tab or workspace of the page in view, or to another running session.
    /// Type to filter, arrows to move, Enter to jump, Esc to close.
    struct Palette: View {
        let pages: WindowPages
        let page: Page
        @Binding var open: Bool

        var body: some View {
            FilterList(prompt: "Jump to a session, workspace or tab", name: "palette", items: items, maxHeight: 360) {
                open = false
            }
            .padding(8)
            .frame(width: 480)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .task { await page.store.loadSessions() }
        }

        /// Tabs first (the usual jump), then workspaces, then the other running sessions, which open as pages.
        private func items(_ filter: String) -> [FilterList.Item] {
            let store = page.store
            let tabs = store.workspaces.flatMap { workspace in
                workspace.tabs.map { tab in
                    FilterList.Item(id: "tab.\(tab.id)", symbol: "apple.terminal", pane: page.stack(tab).first,
                                    title: page.titleText(tab), detail: workspace.label,
                                    act: { page.select(workspace, tab: tab.id) })
                }
            }
            let workspaces = store.workspaces.map { workspace in
                FilterList.Item(id: "workspace.\(workspace.id)", symbol: "square.stack", title: workspace.label,
                                detail: "Workspace") { page.select(workspace) }
            }
            let sessions = store.sessions.filter { $0.running && $0.name != page.id }.map { session in
                FilterList.Item(id: "session.\(session.name)", symbol: "macbook", title: session.name,
                                detail: "Session") { pages.open(session.name) }
            }
            return (tabs + workspaces + sessions).filter { "\($0.title) \($0.detail)".matches(filter) }
        }
    }
#endif
