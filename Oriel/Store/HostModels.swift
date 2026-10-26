import Foundation
import HerdrKit
import Observation

/// The stable objects snapshots land on (see `HostStore`).
extension HostStore {
    /// A close (design D41).
    enum Close {
        case pane(String)
        case tab(String)
        /// The other tabs of a workspace, or the ones to the right of a tab, as they were when the user asked: a tab
        /// made since is not closed.
        case otherTabs([String], right: Bool)
        /// A workspace, with its linked worktrees' workspaces when it has any.
        case workspace(String)

        var paneID: String? {
            if case let .pane(id) = self {
                id
            } else {
                nil
            }
        }
    }

    /// A close waiting for the user's yes, and the programs besides the shells that run in its panes.
    struct Closing {
        let close: Close
        let running: [String]
    }

    @MainActor @Observable
    final class Workspace: Identifiable {
        let id: String
        var label = ""
        var tabs: [Tab] = []
        /// herdr's active tab: a page's first selection in it.
        var activeTabID = ""
        var worktree: Worktree?
        /// Its tabs' strongest agent state (`HostStore.showStrongest`).
        var state: AgentState?
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
        /// Its agent pane with the strongest state (needs you > finished > working > idle), and whether an agent of it
        /// works (`HostStore.showStrongest`).
        var agent: Pane?
        var working = false

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
        /// A new pane's first second, when no ask is made: its shell's startup runs short-lived programs (`gh auth
        /// token`, `brew shellenv` in a .zshrc), and an answer then showed their icons before the shell's.
        @ObservationIgnored var starting = false

        init(id: String) {
            self.id = id
        }

        /// The directory, `~` for home.
        var folder: String? {
            cwd.map { ($0 as NSString).abbreviatingWithTildeInPath }
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
    /// The machine's name, with the session's unless it is `default`.
    var name: String {
        session == "default" ? machine.name : "\(machine.name) · \(session)"
    }

    #if os(macOS)
        /// The sidebar's title: the machine's name for its `default` session, This Mac's own name for This Mac's;
        /// else the session's (user, phase 27).
        var title: String {
            guard session == "default" else { return session }
            return machine.isRemote ? machine.name : Machine.computerName
        }
    #endif

    /// The session in a notification or a Dock row: a remote one with its machine.
    var label: String {
        machine.isRemote ? name : session
    }

    /// Failed while its server runs, not for a missing or old herdr: the client tries again every 2 s.
    var reconnecting: Bool {
        guard case let .failed(error) = state else { return false }
        switch error {
        case .notFound, .unsupported, .disconnected: return false
        default: return isRunning
        }
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

extension HostStore {
    /// One `pane.process_info`; the icon follows. Only the latest ask lands; a failed first one is made again.
    /// `soon`: the user waits on it (a card shows, Return in it): ahead of the first snapshot's asks.
    func askProgram(_ paneID: String, soon: Bool = false) async {
        guard let client, let pane = pane(paneID), !pane.starting else { return }
        pane.asked = true
        pane.asks += 1
        let ask = pane.asks
        await asks.enter(first: soon)
        defer { asks.leave() }
        // A newer ask, a closed pane or a closed page while it waited: no herdr run.
        guard ask == pane.asks, self.client != nil, self.pane(paneID) === pane else { return }
        do {
            let program = try await client.program(paneID)
            if ask == pane.asks {
                pane.program = program
            }
        } catch {
            if ask == pane.asks, pane.program == nil {
                pane.asked = false
            }
        }
    }

    /// Asks what the pane runs: when it is new (or a new terminal under a reused id), and when its agent or title word
    /// changes. A progress title ("build 51%") changes on and on; its first word does not.
    func watchProgram(_ pane: Pane, _ new: HerdrKit.Pane) {
        if new.terminalID != pane.terminalID {
            pane.program = nil
            pane.asked = false
            pane.asks += 1 // the old terminal's answer in flight
        }
        let word = { (title: String?) in title?.split(separator: " ").first }
        if pane.asked, new.agent != pane.agent || word(new.title) != word(pane.terminalTitle) {
            Task { await askProgram(pane.id) }
        }
        // Every pane once, for its tab's icons and the hover card, also in tabs never shown; a failed ask is made
        // again. A new pane a second later, as after Return, and no other ask before (its card's as it shows): a new
        // shell's startup runs short-lived programs. The first snapshot's at once: their shells started long ago.
        if !pane.asked {
            pane.asked = true
            pane.starting = state == .live
            Task {
                if pane.starting {
                    try? await Task.sleep(for: .seconds(1))
                    // A slow startup (a cold nvm) runs on: then until only the shell runs, 3 s more at most.
                    // ponytail: one sample of the shell alone can fall between two startup programs; require two in
                    // a row if a guess still shows.
                    var tries = 0
                    var program = try? await client?.program(pane.id)
                    while tries < 6, program?.isShell == false {
                        tries += 1
                        try? await Task.sleep(for: .milliseconds(500))
                        program = try? await client?.program(pane.id)
                    }
                    // Its last answer, before it stops starting: a tab title shows "New Tab" until then (phase 25).
                    pane.program = program ?? pane.program
                    pane.starting = false
                    if program != nil {
                        return
                    }
                }
                await askProgram(pane.id)
            }
        }
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
