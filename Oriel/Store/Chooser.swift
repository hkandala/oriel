import AppKit
import HerdrKit
import Observation

/// A new pane's chooser (ui/new-pane): Terminal, Agent (which opens its agents under it) or Browser. The app's own
/// state, kept on the session's store so
/// every window shows it; herdr sees a plain shell. Its card is a new tab's or split's stand-in until herdr made the
/// pane, then the pane's terminal, which a move keeps.
@MainActor @Observable
final class Chooser {
    /// An agent it starts: its name, and its command, which is its program icon's id too.
    struct Agent: Equatable {
        let name: String, command: String
    }

    static let agents = [
        Agent(name: "Claude Code", command: "claude"), Agent(name: "Codex", command: "codex"),
        Agent(name: "pi", command: "pi"), Agent(name: "opencode", command: "opencode"),
    ]

    /// A row of the list: `start` is an agent's, by its place in `agents`.
    enum Row: Hashable {
        case terminal, agent, browser, start(Int)
    }

    @ObservationIgnored let standIn: String?
    /// herdr's pane, once it answered.
    @ObservationIgnored var paneID: String?
    @ObservationIgnored var terminalID: String?
    /// Agent is open: its agents show under it.
    var open = false
    var selected = Row.terminal
    /// The picked agent until it is ready: the card shows the loader.
    var starting: Agent?

    init(standIn: String? = nil) {
        self.standIn = standIn
    }

    var rows: [Row] {
        [.terminal, .agent] + (open ? Self.agents.indices.map(Row.start) : []) + [.browser]
    }

    func made(_ pane: HerdrKit.Pane) {
        paneID = pane.id
        terminalID = pane.terminalID
    }

    /// Its number key: the top rows', or the agents' while Agent is open.
    func number(_ row: Row) -> Int? {
        let numbered = open ? Self.agents.indices.map(Row.start) : [.terminal, .agent, .browser]
        return numbered.firstIndex(of: row).map { $0 + 1 }
    }
}

extension Chooser.Row {
    /// Its name, and the line on its right.
    var labels: (name: String, detail: String) {
        switch self {
        case .terminal: ("Terminal", "Shell")
        case .agent: ("Agent", "Coding agent")
        case .browser: ("Browser", "Coming soon")
        case let .start(index): (Chooser.agents[index].name, Chooser.agents[index].command)
        }
    }

    /// Its identifier's last part: an agent's command, else its name.
    var id: String {
        if case let .start(index) = self {
            Chooser.agents[index].command
        } else {
            labels.name.lowercased()
        }
    }
}

extension HostStore {
    /// The card's chooser: by its terminal, else by its stand-in (herdr's pane of a split's stand-in goes by the
    /// stand-in until a snapshot has it).
    func chooser(_ cardID: String) -> Chooser? {
        guard !choosers.isEmpty else { return nil }
        let terminalID = pane(cardID)?.terminalID
        let standIn = ahead.splitPanes.first { $0.value == cardID }?.key ?? cardID
        return choosers.first { $0.terminalID != nil && $0.terminalID == terminalID || $0.standIn == standIn }
    }

    /// A chooser on a new tab's or split's stand-in; `made` gives it herdr's pane.
    func choose(standIn: String) -> Chooser {
        let chooser = Chooser(standIn: standIn)
        choosers.append(chooser)
        return chooser
    }

    /// A chooser on herdr's new pane; with an agent, its loader while the agent starts.
    func choose(_ pane: HerdrKit.Pane?, starting agent: Chooser.Agent? = nil) {
        guard let pane else { return }
        let chooser = Chooser()
        chooser.made(pane)
        choosers.append(chooser)
        if let agent {
            start(agent, chooser)
        }
    }

    func drop(_ chooser: Chooser) {
        choosers.removeAll { $0 === chooser }
    }

    /// ↑ ↓ move through the rows and stop at the ends, Return picks at once, → opens Agent, ← and Esc close it, Esc on
    /// a closed list picks Terminal. The number keys pick the top rows, or the agents while Agent is open. Other keys
    /// do nothing, also while the loader shows.
    func key(_ event: NSEvent, _ chooser: Chooser) {
        guard chooser.starting == nil else { return }
        let rows = chooser.rows, index = rows.firstIndex(of: chooser.selected) ?? 0
        switch event.keyCode {
        case 125, 126: chooser.selected = rows[max(0, min(index + (event.keyCode == 125 ? 1 : -1), rows.count - 1))]
        // → on a closed Agent opens it; ← and Esc close an open one.
        case 124 where chooser.selected == .agent && !chooser.open, 123 where chooser.open, 53 where chooser.open:
            pick(chooser, .agent)
        case 53: drop(chooser)
        case 36, 76:
            if !event.isARepeat {
                pick(chooser, chooser.selected)
            }
        default:
            let number = Int(event.charactersIgnoringModifiers ?? "")
            if let row = rows.first(where: { number != nil && chooser.number($0) == number }) {
                pick(chooser, row)
            }
        }
    }

    /// Agent opens with its first agent selected, or closes with itself selected.
    func pick(_ chooser: Chooser, _ row: Chooser.Row) {
        switch row {
        case .agent:
            chooser.open.toggle()
            chooser.selected = chooser.open ? .start(0) : .agent
        case let .start(index): start(Chooser.agents[index], chooser)
        // Browser too until phase 36.
        case .terminal, .browser: drop(chooser)
        }
    }

    /// Types the agent's command into the pane's shell, as Go to Directory types its `cd`, and shows the loader until
    /// the agent is ready: herdr reports it with a status (all four agents, read from their screens on any machine).
    /// The terminal shows sooner when the shell is in front again (the command failed or ended), or after 10 s.
    func start(_ agent: Chooser.Agent, _ chooser: Chooser) {
        chooser.starting = agent
        Task {
            defer { drop(chooser) }
            let clock = ContinuousClock(), begun = clock.now
            var sent: ContinuousClock.Instant?, shells = 0
            // A new tab's stand-in waits for herdr's pane. A chooser dropped meanwhile (its pane closed) ends it.
            while clock.now - begun < .seconds(10), choosers.contains(where: { $0 === chooser }) {
                if let client, let id = chooser.paneID {
                    guard let since = sent else {
                        guard await (try? client.sendInput(agent.command, keys: ["enter"], pane: id)) != nil else {
                            return
                        }
                        sent = clock.now
                        continue
                    }
                    if let pane = try? await client.pane(id), pane.agent != nil,
                       pane.agentStatus.map({ $0 != .unknown }) == true
                    {
                        return
                    }
                    // Not while a new shell starts (`Pane.starting`): the command waits for its prompt. Twice in a row:
                    // one answer can fall between two of its programs.
                    if clock.now - since > .seconds(1), self.pane(id)?.starting == false {
                        shells = await (try? client.program(id))?.isShell == true ? shells + 1 : 0
                        if shells == 2 {
                            return
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

extension Page {
    /// Start Agent Here: the chooser's pick on a pane that shows it, else a Replace Pane that starts the agent.
    func start(_ agent: Chooser.Agent, in pane: HostStore.Pane) {
        if let chooser = store.chooser(pane.id) {
            if chooser.starting == nil {
                store.start(agent, chooser)
            }
        } else {
            replacePane(pane, Replacement(button: "Start \(agent.name)", chooser: true, agent: agent))
        }
    }

    /// The card keys go to: a new tab's or split's card also before herdr made its pane, while the old card's
    /// terminal keeps the keyboard.
    var keyCardID: String? {
        let newest = newest?.id
        return standIn ?? (newest.map { selectedTab?.tree?.paneIDs.contains($0) == true } == true ? newest : nil)
            ?? keyboardPane?.id
    }

    /// The keyboard card's chooser takes its keys before the terminal under it (`OrielApp`), in the key window (a
    /// floating one too), unless a text field, a panel or the overview has the keyboard.
    static func chooserKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]), let window = NSApp.keyWindow,
              !(window.firstResponder is NSText) else { return false }
        let target: (HostStore, String)?
        if let pages = WindowPages.windows.first(where: { $0.window === window }) {
            guard !pages.overview, !pages.panelOpen, let page = pages.current else { return false }
            target = page.keyCardID.map { (page.store, $0) }
        } else if let view = window.firstResponder as? PaneSurfaceView, let store = view.store(),
                  let id = view.terminal?.paneID
        {
            target = (store, id)
        } else {
            target = nil
        }
        guard let (store, id) = target, let chooser = store.chooser(id) else { return false }
        store.key(event, chooser)
        return true
    }
}
