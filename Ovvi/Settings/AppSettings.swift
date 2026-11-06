import GhosttyTerminal
import SwiftUI

/// The app's settings (ui/settings), for the command list and the Settings window. Each is one key in the app's
/// defaults.
struct AppSettings: DynamicProperty {
    @AppStorage("appearance") var appearance = Appearance.dark
    @AppStorage("interfaceStyle") var style = InterfaceStyle.glass
    @AppStorage("fontSize") var fontSize = PaneTerminal.fontSize
    @AppStorage("focusFollowsMouse") var followMouse = false
    /// The notifications' switches (status#notifications), all on by default.
    @AppStorage(Notifications.needsYou) var notifyNeedsYou = true
    @AppStorage(Notifications.finished) var notifyFinished = true
    @AppStorage(Notifications.fromAgents) var notifyFromAgents = true
    /// A monospaced family; empty: the system's (SF Mono).
    @AppStorage("terminalFont") var terminalFont = ""
    @AppStorage("cursorStyle") var cursorStyle = TerminalCursorStyle.block
    @AppStorage("cursorBlink") var cursorBlink = true
    @AppStorage("optionKey") var optionKey = OptionKey.characters
    @AppStorage("copyOnSelect") var copyOnSelect = false
    /// What a new agent's card shows first.
    @AppStorage("agentView") var agentView = AgentView.terminal
    /// Seconds an idle agent the user has seen waits before it moves to Settled; 0: never.
    @AppStorage("settleAfter") var settleAfter = 3 * 3600.0
    /// The Agents view's pins (`AgentPin`) in pin order, a JSON list.
    @AppStorage(AgentPin.key) var pins = ""

    /// What the terminals take from the settings (`PaneTerminal.configure`): a change configures them again.
    var terminal: [String] {
        [terminalFont, "\(fontSize)", cursorStyle.rawValue, "\(cursorBlink)", optionKey.rawValue, "\(copyOnSelect)"]
    }
}

/// What Option does in a terminal: types the macOS characters, or acts as Meta (both keys, or the left one).
enum OptionKey: String, CaseIterable {
    case characters, meta, left

    /// libghostty's `macos-option-as-alt`.
    var ghostty: String {
        switch self {
        case .characters: "false"
        case .meta: "true"
        case .left: "left"
        }
    }
}

enum AgentView: String {
    case terminal, chat
}
