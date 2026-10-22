import Foundation
import HerdrKit
import Observation

/// The stable objects snapshots land on (see `HostStore`).
extension HostStore {
    @MainActor @Observable
    final class Workspace: Identifiable {
        let id: String
        var label = ""
        var status = AgentStatus.idle
        var tabs: [Tab] = []
        /// The app's own selection, never herdr's focus. Starts at herdr's active tab.
        var selectedTabID: String?

        init(id: String) {
            self.id = id
        }
    }

    @MainActor @Observable
    final class Tab: Identifiable {
        let id: String
        var label = ""
        var status = AgentStatus.idle
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

    /// Selects the tab before or after the selected one, round the ends.
    func step(_ offset: Int) {
        guard let workspace = selectedWorkspace, !workspace.tabs.isEmpty else { return }
        let tabs = workspace.tabs
        let index = tabs.firstIndex { $0.id == workspace.selectedTabID } ?? 0
        workspace.selectedTabID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    /// The tab's title, from herdr's label; herdr's default label (a bare number) gives the front card's program
    /// and folder instead (D65).
    func title(_ tab: Tab) -> (name: String, folder: String?) {
        guard !tab.label.isEmpty, tab.label.allSatisfy(\.isNumber), let pane = stack(tab).first,
              let name = pane.programName else { return (tab.label, nil) }
        return (name, pane.folder)
    }

    func workspace(of tabID: String) -> Workspace? {
        workspaces.first { $0.tabs.contains { $0.id == tabID } }
    }

    /// The title in one string, for the window title and menus.
    func titleText(_ tab: Tab) -> String {
        let title = title(tab)
        return [title.name, title.folder ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
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
