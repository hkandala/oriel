import SwiftUI

/// herdr's workspaces as rows (the tabs are in the title row, D45), and a filter at the bottom.
struct Sidebar: View {
    let store: HostStore
    @State private var filter = ""

    var body: some View {
        let workspaces = store.workspaces.filter { $0.label.matches(filter) }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(workspaces) { WorkspaceRow(workspace: $0, store: store) }
                    if workspaces.isEmpty, !store.workspaces.isEmpty {
                        Text("No matching workspaces").foregroundStyle(.secondary).padding(8)
                    }
                }
                .padding([.horizontal, .bottom], 8)
            }
            .scrollIndicators(.never)
            HStack(spacing: 2) {
                FilterField(prompt: "Filter", text: $filter, identifier: "sidebar.filter")
                #if os(macOS)
                    .onExitCommand { filter = "" }
                #endif
                    .padding(.trailing, 4)
                IconButton(symbol: "rectangle.stack.badge.plus", help: "New Workspace") {
                    Task { await store.newWorkspace() }
                }
                .disabled(store.state != .live || store.writing)
                .accessibilityIdentifier("sidebar.new-workspace")
                // ponytail: no-op until remote hosts
                IconButton(symbol: "network", help: "Add Remote Host") {}
            }
            .padding(8)
        }
        // On the window background, as in the reference: only the pane cards are lighter.
        .frame(width: 240)
    }
}

/// A workspace row (phase 14 restyles it); clicking it selects the workspace at its own selected tab.
private struct WorkspaceRow: View {
    let workspace: HostStore.Workspace
    let store: HostStore

    var body: some View {
        let selected = workspace.id == store.selectedWorkspaceID
        Button { store.selectedWorkspaceID = workspace.id } label: {
            HStack {
                Text(workspace.label).lineLimit(1)
                Spacer()
                StatusGlyph(status: workspace.status)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
        .buttonStyle(ChromeStyle(selected: selected, radius: 10))
        .accessibilityIdentifier("workspace.\(workspace.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
