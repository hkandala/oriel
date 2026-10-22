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
        /// What runs besides the shell, from the last `pane.process_info`; nil while only the shell runs.
        var program: Program?
        /// herdr was asked for the program at least once.
        @ObservationIgnored var asked = false

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

        /// The program's name for the card header: herdr's agent, else the foreground process.
        var programName: String? {
            agent ?? program?.name
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
