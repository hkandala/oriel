import AppKit
import HerdrKit
import Observation

/// A new pane's chooser (ui/new-pane): Terminal, Agent (which opens its agents under it), then every kind with a
/// chooser row in the registry: Browser, File Explorer, Git and the user's plugins. The app's own state, kept on the
/// session's store so every window shows it; herdr sees a plain shell. Its
/// card is a new tab's or split's stand-in until herdr made the pane, then the pane's terminal, which a move keeps.
@MainActor @Observable
final class Chooser {
    /// An agent it starts: its name, and its command, which is its program icon's id too.
    struct Agent: Equatable {
        let name: String, command: String
    }

    static let agents = [
        Agent(name: "Claude Code", command: "claude"), Agent(name: "Codex", command: "codex"),
        Agent(name: "Pi", command: "pi"), Agent(name: "OpenCode", command: "opencode"),
    ]

    /// A row of the list: `start` is an agent's, by its place in `agents`; `plugin` a registry kind's, by its id.
    enum Row: Hashable {
        case terminal, agent, plugin(String), start(Int)
    }

    static let plugins = Registry.all.filter { $0.chooser != nil }.map { Row.plugin($0.id) }

    @ObservationIgnored let standIn: String?
    /// herdr's pane, once it answered.
    var paneID: String?
    var terminalID: String?
    /// Agent is open: its agents show under it.
    var open = false
    var selected = Row.terminal
    /// The picked agent until it is ready: the card shows the loader.
    var starting: Agent?
    /// A kind was picked: the card shows its loader while its pane takes this one's place.
    var opening: PluginManifest?

    init(standIn: String? = nil) {
        self.standIn = standIn
    }

    var rows: [Row] {
        [.terminal, .agent] + (open ? Self.agents.indices.map(Row.start) : []) + Self.plugins
    }

    func made(_ pane: HerdrKit.Pane) {
        paneID = pane.id
        terminalID = pane.terminalID
    }

    /// Its number key: the top rows', or the agents' while Agent is open.
    func number(_ row: Row) -> Int? {
        let numbered = open ? Self.agents.indices.map(Row.start) : [.terminal, .agent] + Self.plugins
        return numbered.firstIndex(of: row).map { $0 + 1 }
    }
}

extension Chooser.Row {
    /// Its name, and the line on its right.
    var labels: (name: String, detail: String) {
        switch self {
        case .terminal: ("Terminal", "Shell")
        case .agent: ("Agent", "Coding agent")
        case let .plugin(id): Registry.plugin(id).map { ($0.chooser ?? $0.name, $0.description) } ?? (id, "")
        case let .start(index): (Chooser.agents[index].name, Chooser.agents[index].command)
        }
    }

    /// Its identifier's last part: an agent's command, a plugin's id, else its name.
    var id: String {
        if case let .start(index) = self {
            Chooser.agents[index].command
        } else if case let .plugin(id) = self {
            id
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
        return choosers.first {
            $0.standIn == cardID || $0.paneID == cardID || $0.terminalID != nil && $0.terminalID == terminalID
        }
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

    /// The closed terminals' choosers and chats (a chat holds its whole history). Written only when one went: it runs
    /// at every snapshot, and Observation notifies on a write that changes nothing, which made the open menu bar
    /// rebuild under the pointer (its tab titles read `choosers`) and lose a click.
    func drop(closed: Set<String>) {
        guard !closed.isEmpty else { return }
        if choosers.contains(where: { $0.terminalID.map(closed.contains) == true }) {
            choosers.removeAll { $0.terminalID.map(closed.contains) == true }
        }
        if chats.keys.contains(where: closed.contains) {
            chats = chats.filter { !closed.contains($0.key) }
        }
    }

    /// ↑ ↓ move through the rows and stop at the ends, Return picks at once, → opens Agent, ← and Esc close it, Esc on
    /// a closed list picks Terminal. The number keys pick the top rows, or the agents while Agent is open. Other keys
    /// do nothing, also while the loader shows.
    func key(_ event: NSEvent, _ chooser: Chooser, page: Page?) {
        // A held key moves on, but picks once: a held 2 would open Agent, then start Codex.
        guard chooser.starting == nil, chooser.opening == nil,
              !event.isARepeat || [125, 126].contains(event.keyCode) else { return }
        let rows = chooser.rows, index = rows.firstIndex(of: chooser.selected) ?? 0
        switch event.keyCode {
        case 125, 126: chooser.selected = rows[max(0, min(index + (event.keyCode == 125 ? 1 : -1), rows.count - 1))]
        // → on a closed Agent opens it; ← and Esc close an open one.
        case 124 where chooser.selected == .agent && !chooser.open, 123 where chooser.open, 53 where chooser.open:
            pick(chooser, .agent, page: page)
        case 53: drop(chooser)
        case 36, 76: pick(chooser, chooser.selected, page: page)
        default:
            let number = Int(event.charactersIgnoringModifiers ?? "")
            if let row = rows.first(where: { number != nil && chooser.number($0) == number }) {
                pick(chooser, row, page: page)
            }
        }
    }

    /// Agent opens with its first agent selected, or closes with itself selected. `page`: where it was picked.
    func pick(_ chooser: Chooser, _ row: Chooser.Row, page: Page?) {
        switch row {
        case .agent:
            chooser.open.toggle()
            chooser.selected = chooser.open ? .start(0) : .agent
        case let .start(index): start(Chooser.agents[index], chooser)
        case let .plugin(id):
            if let plugin = Registry.plugin(id) {
                page?.open(plugin, chooser)
            }
        case .terminal: drop(chooser)
        }
    }

    /// Types the agent's command (with Oriel's chat flags, ui/chat-view#launch-flags) into the pane's shell,
    /// as Go to Directory types its `cd`, and shows the loader until the agent is ready: herdr reports it with a status
    /// (all four agents, read from their screens on any machine).
    /// The terminal shows sooner when the shell is in front again (the command failed or ended), or after 10 s.
    /// `resume`: Relaunch with Chat's session; the agent in the pane quits first.
    func start(_ agent: Chooser.Agent, _ chooser: Chooser, resume: String? = nil) {
        // Once: a double click's second click lands on the row as it fades out.
        guard chooser.starting == nil else { return }
        chooser.starting = agent
        Task {
            defer { drop(chooser) }
            let resumed = await restart(agent, chooser, resume)
            guard resume == nil || resumed != nil else { return }
            let clock = ContinuousClock(), begun = clock.now
            var sent: ContinuousClock.Instant?, shells = 0, line: String?
            // A new tab's stand-in waits for herdr's pane. A chooser dropped meanwhile (its pane closed) ends it.
            while clock.now - begun < .seconds(10), choosers.contains(where: { $0 === chooser }) {
                if let client, let id = chooser.paneID {
                    guard let since = sent else {
                        // With Oriel's flags first; once more without them when the shell came back at once (a build
                        // that refuses them starts with no chat rather than not at all).
                        let next = line == nil ? await firstLine(agent, resumed) : agent.command
                        // Its pane may have closed during the launch's run on the machine.
                        guard choosers.contains(where: { $0 === chooser }),
                              await (try? client.sendInput(next, keys: ["enter"], pane: id)) != nil
                        else {
                            return
                        }
                        line = next
                        sent = clock.now
                        continue
                    }
                    if let pane = try? await client.pane(id), pane.agent != nil,
                       pane.agentStatus.map({ $0 != .unknown }) == true
                    {
                        // Its launch marker before the loader goes, so a chat pane shows its chat at once.
                        await askProgram(id, soon: true)
                        return
                    }
                    // Not while a new shell starts (`Pane.starting`): the command waits for its prompt. Twice in a row:
                    // one answer can fall between two of its programs.
                    if clock.now - since > .seconds(1), self.pane(id)?.starting == false {
                        shells = await (try? client.program(id))?.isShell == true ? shells + 1 : 0
                        if shells == 2 {
                            // A resume's plain command would start another session.
                            guard line != agent.command, resume == nil else { return }
                            (sent, shells) = (nil, 0)
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

extension HostStore {
    /// Relaunch with Chat (ui/chat-view#which-panes-have-it): an agent herdr knows, started without Oriel's flags, in a
    /// session herdr knows, again with the flags in that session, with the chooser's loader meanwhile.
    func enableChat(_ pane: Pane) {
        guard let agent = Chooser.agents.first(where: { $0.command == pane.agent }), let session = pane.session,
              chooser(pane.id) == nil else { return }
        let chooser = Chooser()
        chooser.paneID = pane.id
        chooser.terminalID = pane.terminalID
        choosers.append(chooser)
        pane.relaunched = true
        start(agent, chooser, resume: session)
    }

    /// The agent's line with Oriel's flags (Relaunch with Chat's, made before its agent quit), else its command.
    private func firstLine(_ agent: Chooser.Agent, _ resumed: String?) async -> String {
        if let resumed {
            return resumed
        }
        return await ChatAdapters.launch(agent.command, on: machine.exec()) ?? agent.command
    }

    /// Relaunch with Chat's launch line, made first so a failed run on the machine leaves the agent running, once the
    /// agent quit; nil (with a notice) when either failed, and with no session.
    private func restart(_ agent: Chooser.Agent, _ chooser: Chooser, _ session: String?) async -> String? {
        guard let session else { return nil }
        guard let id = chooser.paneID,
              let line = await ChatAdapters.launch(agent.command, resume: session, on: machine.exec())
        else {
            await show(Notice(text: "\(agent.name) could not start with chat"))
            return nil
        }
        guard await quit(id, agent, chooser) else {
            // A closed pane's chooser is gone: nothing to say.
            if choosers.contains(where: { $0 === chooser }) {
                await show(Notice(text: "\(agent.name) did not quit"))
            }
            return nil
        }
        return line
    }

    /// Quits the agent as its user would: a turn or a dialog stopped first, the prompt cleared (⌃C, which alone ends
    /// OpenCode with an empty prompt), then its quit command. True once only the shell runs and herdr let go of the
    /// agent, within 10 s, while its chooser is there (its pane did not close).
    private func quit(_ paneID: String, _ agent: Chooser.Agent, _ chooser: Chooser) async -> Bool {
        guard let client, let adapter = ChatAdapters.adapter(agent.command) else { return false }
        if pane(paneID)?.state.map({ $0 == .working || $0 == .needsYou }) == true {
            try? await client.sendKeys(adapter.stopKeys, pane: paneID)
            try? await Task.sleep(for: .seconds(1))
        }
        try? await client.sendKeys(["ctrl+c"], pane: paneID)
        var typed = false
        let clock = ContinuousClock(), begun = clock.now
        while clock.now - begun < .seconds(10), choosers.contains(where: { $0 === chooser }) {
            // OpenCode stops its server first: the quit command would land in the shell.
            try? await Task.sleep(for: .seconds(typed ? 0.3 : 2))
            guard await (try? client.program(paneID))?.isShell == true else {
                if !typed {
                    typed = true
                    try? await client.sendInput(adapter.quit, keys: ["enter"], pane: paneID)
                }
                continue
            }
            if await (try? client.pane(paneID))?.agent == nil {
                return true
            }
        }
        return false
    }
}

extension Page {
    /// Start Agent Here: the chooser's pick on a pane that shows it, else a Replace Pane that starts the agent.
    func start(_ agent: Chooser.Agent, in pane: HostStore.Pane) {
        if let chooser = store.chooser(pane.id) {
            store.start(agent, chooser)
        } else {
            replacePane(pane, Replacement(button: "Start \(agent.name)", chooser: true, agent: agent))
        }
    }

    /// The card keys go to: a new tab's or split's card also before its terminal took the keyboard from the old
    /// card's (herdr's split answer comes before the snapshot that shows it).
    var keyCardID: String? {
        standIn ?? newest?.id ?? keyboardPane?.id
    }

    /// The keyboard card's chooser takes its keys before the terminal under it (`OrielApp`), in the key window (a
    /// floating one too), unless a text field, a panel or the overview has the keyboard.
    static func chooserKey(_ event: NSEvent) -> Bool {
        // ⌃ and ⌥ keys too, or ⌃D would end the hidden shell: the app's ⌃ keys are second shortcuts, taken before.
        // ⌘V too, which would paste into the hidden shell; the app's other ⌘ keys work as usual.
        let paste = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers == "v"
        guard !event.modifierFlags.contains(.command) || paste, let window = NSApp.keyWindow,
              !(window.firstResponder is NSText) else { return false }
        let target: (Page, String)?
        if let pages = WindowPages.windows.first(where: { $0.window === window }) {
            guard !pages.overview, !pages.panelOpen, let page = pages.current, !page.store.choosers.isEmpty else {
                return false
            }
            target = page.keyCardID.map { (page, $0) }
        } else if let view = window.firstResponder as? PaneSurfaceView, let store = view.store(),
                  let id = view.terminal?.paneID,
                  // The page that floats it.
                  let page = WindowPages.windows.lazy.flatMap(\.withFloats)
                      .first(where: { $0.store === store && store.pane(id).map($0.floats) == true })
        {
            target = (page, id)
        } else {
            target = nil
        }
        guard let (page, id) = target, let chooser = page.store.chooser(id) else { return false }
        if !paste {
            page.store.key(event, chooser, page: page)
        }
        return true
    }
}
