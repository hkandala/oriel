#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// A workspace: its state slot and name, and its branch with ahead and behind on a second line in a repository.
    /// A linked worktree sits indented under its repository's row, on a guide line.
    struct WorkspaceRow: View {
        let workspace: HostStore.Workspace
        let parent: HostStore.Workspace?
        let page: Page
        /// A worktree row follows: the guide line starts under this row's state slot.
        let guideBelow: Bool
        /// The first and the last group's workspace: they cannot move up or down.
        let ends: (first: String?, last: String?)
        @State private var renaming = false
        @Environment(\.look) private var look

        var body: some View {
            let selected = workspace.id == page.selectedWorkspaceID
            let git = workspace.git
            let state = page.store.strongest(workspace.tabs.map(\.id))?.state
            let height: CGFloat = git == nil ? 30 : 44
            Button { page.select(workspace) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        StateIcon(state: state)
                        Text(workspace.label).font(.system(size: 13)).lineLimit(1).opacity(renaming ? 0 : 1)
                            .foregroundStyle(selected ? look.selected : look.chrome)
                    }
                    if let git {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                            Text(git.branch).lineLimit(1).truncationMode(.middle)
                            if git.ahead > 0 {
                                Text("↑\(git.ahead)").foregroundStyle(look.finished)
                            }
                            if git.behind > 0 {
                                Text("↓\(git.behind)").foregroundStyle(look.error)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            }
            .buttonStyle(ChromeStyle(selected: selected, radius: 10))
            .simultaneousGesture(TapGesture(count: 2).onEnded { startRenaming() })
            .dragSource(.workspace(workspace.id), page: page)
            .accessibilityIdentifier("workspace.\(workspace.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue([state?.word, git.map { "\($0.branch) ahead \($0.ahead) behind \($0.behind)" },
                                 parent.map { "worktree of \($0.label)" }].compactMap(\.self).joined(separator: ", "))
            .overlay(alignment: .leading) {
                if renaming {
                    // Enter: herdr's label; the snapshot after it shows it.
                    RenameField(prompt: "Workspace Name", initial: workspace.label, commit: { label in
                        Task { await page.store.rename(workspace: workspace.id, label: label) }
                    }, end: stopRenaming)
                        .font(.system(size: 13))
                        .padding(.leading, 8 + 14 + 6)
                        .padding(.trailing, 8)
                        .frame(height: 30, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .accessibilityIdentifier("workspace.\(workspace.id).rename")
                }
            }
            // Writes only while the session runs: a stopped one keeps its last rows.
            .contextMenu { menu.disabled(page.store.state != .live) }
            .padding(.leading, parent == nil ? 0 : 14)
            // From the repository's state slot (8 + 7 pt in) down along its worktrees.
            .background(alignment: .topLeading) {
                if parent != nil || guideBelow {
                    Rectangle().fill(.separator).frame(width: 1)
                        .padding(.top, parent == nil ? 22 : 0)
                        .padding(.bottom, guideBelow ? -2 : height / 2)
                        .padding(.leading, 15)
                }
            }
        }

        @ViewBuilder
        private var menu: some View {
            let store = page.store
            let first = ends.first == workspace.id, last = ends.last == workspace.id
            Button("New Tab") { Task { await page.newTab(in: workspace) } }
            Button("Rename Workspace") { startRenaming() }
            // A worktree moves with its repository's row.
            Button("Move Up") { Task { await store.move(workspace: workspace.id, by: -1) } }
                .disabled(parent != nil || first)
            Button("Move Down") { Task { await store.move(workspace: workspace.id, by: 1) } }
                .disabled(parent != nil || last)
            Divider()
            Button("Close Workspace") { page.closing = .workspace(workspace.id) }
        }

        /// Not while the session is stopped (a double-click too): the rename would fail.
        private func startRenaming() {
            guard page.store.state == .live else { return }
            renaming = true
        }

        /// The keyboard goes back to the selected tab's card.
        private func stopRenaming() {
            guard renaming else { return }
            renaming = false
            page.focusKeyboardCard()
        }
    }
#endif
