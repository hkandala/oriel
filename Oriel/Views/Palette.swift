import HerdrKit
import SwiftUI

/// ⌘K: a floating glass panel to jump to a session, workspace or tab. Type to filter, arrows to move, Enter to
/// jump, Esc to close.
struct Palette: View {
    @Binding var store: HostStore
    @Binding var open: Bool

    var body: some View {
        FilterList(prompt: "Jump to a session, workspace or tab", name: "palette", items: items, maxHeight: 360) {
            open = false
        }
        .padding(8)
        .frame(width: 480)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .task { await store.loadSessions() }
    }

    /// Tabs first (the usual jump), then workspaces, then the other running sessions.
    private func items(_ filter: String) -> [FilterList.Item] {
        let tabs = store.workspaces.flatMap { workspace in
            workspace.tabs.map { tab in
                FilterList.Item(id: "tab.\(tab.id)", symbol: "apple.terminal", pane: store.stack(tab).first,
                                title: store.titleText(tab), detail: workspace.label, act: {
                                    store.selectedWorkspaceID = workspace.id
                                    workspace.selectedTabID = tab.id
                                })
            }
        }
        let workspaces = store.workspaces.map { workspace in
            FilterList.Item(id: "workspace.\(workspace.id)", symbol: "square.stack", title: workspace.label,
                            detail: "Workspace") { store.selectedWorkspaceID = workspace.id }
        }
        let sessions = store.sessions.filter { $0.running && $0.name != store.session }.map { session in
            FilterList.Item(id: "session.\(session.name)", symbol: "macbook", title: session.name, detail: "Session") {
                store = HostStore(session: session.name)
            }
        }
        return (tabs + workspaces + sessions).filter { "\($0.title) \($0.detail)".matches(filter) }
    }
}
