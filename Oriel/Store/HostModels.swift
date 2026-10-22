import Foundation
import HerdrKit
import Observation

/// The stable objects snapshots land on (see `HostStore`).
extension HostStore {
    /// A close waiting for the user's yes (design D41).
    enum Close {
        /// The pane and the program running in it.
        case pane(String, program: String)
        case tab(String)
        /// The other tabs of a workspace, as they were when the user asked: a tab made since is not closed.
        case otherTabs([String])
        /// A workspace, with its linked worktrees' workspaces when it has any.
        case workspace(String)
    }

    @MainActor @Observable
    final class Workspace: Identifiable {
        let id: String
        var label = ""
        var tabs: [Tab] = []
        /// herdr's active tab: a page's first selection in it.
        var activeTabID = ""
        var worktree: Worktree?
        /// The branch of its root (`worktree.checkout_path`, else its first pane's cwd); nil when not a repository.
        var git: GitStatus?
        /// The root of the last git run.
        @ObservationIgnored var gitRoot: String?

        init(id: String) {
            self.id = id
        }
    }

    @MainActor @Observable
    final class Tab: Identifiable {
        let id: String
        var label = ""
        var tree: SplitNode?

        init(id: String) {
            self.id = id
        }
    }

    @MainActor @Observable
    final class Pane: Identifiable {
        let id: String
        var label: String?
        var cwd: String?
        /// The tab's focused pane, as herdr has it.
        var focused = false
        var tabID = ""
        var terminalID: String?
        /// herdr's agent kind, detected or reported.
        var agent: String?
        /// The terminal title without herdr's status glyphs.
        var terminalTitle: String?
        /// Its agent's state (D14); nil without an agent.
        var state: AgentState?
        /// When the app saw the state change, for the ages.
        var since: Date?
        /// The agent's name: herdr's `display_agent`, else its kind.
        var agentName: String?
        /// What runs in the foreground (the shell when nothing else does), from the last `pane.process_info`.
        var program: Program?
        /// herdr was asked for the program at least once.
        @ObservationIgnored var asked = false
        /// Asks made, so only the latest answer lands.
        @ObservationIgnored var asks = 0

        init(id: String) {
            self.id = id
        }

        /// The directory, `~` for home.
        var folder: String? {
            cwd.map { ($0 as NSString).abbreviatingWithTildeInPath }
        }

        /// The close dialog's name for it: the label, else the directory.
        var title: String {
            label ?? folder ?? "terminal"
        }

        /// The card header's parts: the label alone, else the program and the folder, as in Rex ("zsh", "~").
        var header: (name: String?, folder: String) {
            let name = label == nil ? programName : nil
            return (name, label ?? folder ?? (name == nil ? "terminal" : ""))
        }

        var cardTitle: String {
            let (name, folder) = header
            return [name, folder].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
        }

        /// The program's name for the card header: herdr's agent, else the foreground process ("zsh" for the shell).
        var programName: String? {
            agent ?? program?.title
        }

        /// The placeholder icon's letter.
        var letter: String? {
            programName?.prefix(1).uppercased()
        }

        /// Its program icon's catalog id.
        var iconID: String {
            programIcons.iconID(agent: agent, program: program, title: terminalTitle)
        }
    }
}

extension HostStore {
    /// "This Mac" for the default session, "This Mac · ‹session›" for the others.
    static func name(_ session: String) -> String {
        session == "default" ? "This Mac" : "This Mac · \(session)"
    }

    /// The pane of these tabs with the strongest state (needs you > finished > working > idle); nil without agents.
    func strongest(_ tabIDs: [String]) -> Pane? {
        panes.filter { $0.state != nil && tabIDs.contains($0.tabID) }.max { $0.state ?? .idle < $1.state ?? .idle }
    }

    func workspace(of tabID: String) -> Workspace? {
        workspaces.first { $0.tabs.contains { $0.id == tabID } }
    }

    /// The workspace of the repository a linked worktree's workspace sits under: the first one with the same
    /// `repo_key` that is not a linked worktree.
    func parent(of workspace: Workspace) -> Workspace? {
        guard let worktree = workspace.worktree, worktree.isLinkedWorktree else { return nil }
        return workspaces.first { $0.worktree?.repoKey == worktree.repoKey && $0.worktree?.isLinkedWorktree == false }
    }

    func worktrees(of workspaceID: String) -> [Workspace] {
        workspaces.filter { parent(of: $0)?.id == workspaceID }
    }

    /// The sidebar's rows in groups: each workspace in herdr's order, its linked worktrees right after it.
    var groups: [[Workspace]] {
        workspaces.filter { parent(of: $0) == nil }.map { [$0] + worktrees(of: $0.id) }
    }
}

/// Keeps the object of each id that stays, makes the new ones, and replaces the list only when its
/// ids changed, so views of the list redraw only then.
@MainActor
func reuse<Owner: AnyObject, Object: Identifiable<String>, Item: Identifiable<String>>(
    _ owner: Owner,
    _ list: ReferenceWritableKeyPath<Owner, [Object]>,
    _ items: [Item],
    _ make: (String) -> Object,
    _ update: (Object, Item) -> Void,
) {
    let old = Dictionary(owner[keyPath: list].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let new = items.map { item in
        let object = old[item.id] ?? make(item.id)
        update(object, item)
        return object
    }
    if new.map(\.id) != owner[keyPath: list].map(\.id) {
        owner[keyPath: list] = new
    }
}
