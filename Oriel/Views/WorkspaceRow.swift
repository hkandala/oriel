import HerdrKit
import SwiftUI

/// A workspace: its name and its state on the right as t3code's thread rows show it, and its branch with ahead and
/// behind on a second line in a repository. A linked worktree sits indented under its repository's row, on a guide
/// line.
struct WorkspaceRow: View {
    let workspace: HostStore.Workspace
    let parent: HostStore.Workspace?
    let page: Page
    /// A worktree row follows: the guide line starts under this row.
    let guideBelow: Bool
    /// The first and the last group's workspace: they cannot move up or down.
    let ends: (first: String?, last: String?)
    /// 1…9 while ⌃⌘ is held: "⌃⌘1" at the end of the name's line.
    let keycap: Int?
    @State private var renaming = false
    @Environment(\.look) private var look

    var body: some View {
        let selected = workspace.id == page.selectedWorkspaceID
        let git = workspace.git
        let state = workspace.state
        let label = state?.label(look, since: state == .working ? workspace.since : nil)
        let height: CGFloat = git == nil ? 30 : 44
        Button {
            page.select(workspace)
            // AppKit's double-click, counted from the events' times: SwiftUI's TapGesture(count: 2) missed one
            // while the app was busy drawing the first click's selection.
            if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.clickCount == 2 {
                startRenaming()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workspace.label).font(.system(size: 13, weight: state?.calls == true ? .medium : .regular))
                        .lineLimit(1).opacity(renaming ? 0 : 1)
                        .foregroundStyle(selected ? look.selected : look.chrome)
                    Spacer(minLength: 0)
                    // The room of the keycap, else of the state: the name gives way to it.
                    if let keycap {
                        Keycap(text: "⌃⌘\(keycap)").hidden()
                    } else {
                        label.hidden()
                    }
                }
                if let git {
                    HStack(spacing: 4) {
                        Image(symbol: "source.branch").font(.system(size: 10))
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
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        }
        .buttonStyle(ChromeStyle(selected: selected, radius: 10))
        .dragSource(.workspace(workspace.id), page: page)
        .accessibilityIdentifier("workspace.\(workspace.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue([state?.word, git.map { "\($0.branch) ahead \($0.ahead) behind \($0.behind)" },
                             parent.map { "worktree of \($0.label)" }].compactMap(\.self).joined(separator: ", "))
        // At the end of the name's line, never over the name. Over the button, so a test sees it.
        .overlay(alignment: .topTrailing) {
            if let keycap, !renaming {
                Keycap(text: "⌃⌘\(keycap)").frame(height: 30).padding(.trailing, 8)
                    .transition(Keycap.transition)
                    .accessibilityIdentifier("workspace.\(workspace.id).keycap")
            } else if let label, !renaming {
                // Its own element, for tests; the row's value has the state word for VoiceOver.
                label.frame(height: 30).padding(.trailing, 8).allowsHitTesting(false)
                    .accessibilityIdentifier("workspace.\(workspace.id).state")
            }
        }
        .overlay(alignment: .leading) {
            if renaming {
                // Enter: herdr's label; the snapshot after it shows it.
                RenameField(prompt: "Workspace Name", initial: workspace.label, commit: { label in
                    Task { await page.store.rename(workspace: workspace.id, label: label) }
                }, end: stopRenaming)
                    .font(.system(size: 13))
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .frame(height: 30, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityIdentifier("workspace.\(workspace.id).rename")
            }
        }
        // Writes only while the session runs: a stopped one keeps its last rows.
        .contextMenu { menu.disabled(page.store.state != .live) }
        .padding(.leading, parent == nil ? 0 : 14)
        // From under the repository's row, 15 pt in, down along its worktrees.
        .background(alignment: .topLeading) {
            if parent != nil || guideBelow {
                Rectangle().fill(.separator).frame(width: 1)
                    .padding(.top, parent == nil ? height : 0)
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
        Button("Close Workspace") { page.close(.workspace(workspace.id)) }
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
