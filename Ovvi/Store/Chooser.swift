import AppKit
import HerdrKit
import Observation

/// A new pane's chooser (ui/new-pane): Terminal, Agent (which opens its agents under it), then every kind with a
/// chooser row in the registry: Browser, File Explorer, Git and the user's plugins. The app's own state, kept on the
/// session's store so every window shows it; herdr sees a plain shell. Its
/// card is a new tab's or split's stand-in until herdr made the pane, then the pane's terminal, which a move keeps.
@MainActor @Observable
final class Chooser {
    /// An agent it starts: its name, its command, which is its program icon's id too, and how to install it.
    struct Agent: Equatable {
        let name: String, command: String, install: String
    }

    static let agents = [
        Agent(name: "Claude Code", command: "claude", install: "npm install -g @anthropic-ai/claude-code"),
        Agent(name: "Codex", command: "codex", install: "npm install -g @openai/codex"),
        Agent(name: "Pi", command: "pi", install: "npm install -g @mariozechner/pi-coding-agent"),
        Agent(name: "OpenCode", command: "opencode", install: "npm install -g opencode-ai"),
    ]

    /// The agents the user did not turn off in New Pane (Settings ▸ Agents), as rows.
    static var shownAgents: [Row] {
        agents.indices.filter { !Registry.hiddenInNewPane(agents[$0].command) }.map(Row.start)
    }

    /// The defaults key of an agent's extra arguments (Settings ▸ Agents).
    static func argumentsKey(_ command: String) -> String {
        "agentArguments.\(command)"
    }

    /// The extra arguments as they go into the typed line, after a space; "" with none.
    static func arguments(_ command: String) -> String {
        let text = allowed(UserDefaults.standard.string(forKey: argumentsKey(command)) ?? "")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "" : " " + text
    }

    /// The text without a line break, a quote or a backslash: they go into a typed line, as the hooks' rule (D76).
    static func allowed(_ text: String) -> String {
        text.filter { !"\"'\\".contains($0) && !$0.isNewline }
    }

    /// An agent the window's machine does not have (`WindowPages.agents`, nil while unknown): no pick, no key.
    static func missing(_ row: Row, _ installed: Set<String>?) -> Bool {
        guard let agent = row.agent, let installed else { return false }
        return !installed.contains(agent.command)
    }

    /// A row of the list: `start` is an agent's, by its place in `agents`; `plugin` a registry kind's, by its id.
    enum Row: Hashable {
        case terminal, agent, plugin(String), start(Int)
    }

    static var plugins: [Row] {
        Registry.all.filter(Registry.inNewPane).map { Row.plugin($0.id) }
    }

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
    /// The agent's line went into the shell: `ovvi agent` and `ovvi chat` answer then.
    @ObservationIgnored var typed = false
    /// The folder its pick starts in, from its folder line (`NewPaneFolder`); nil: the pane's own.
    var folder: String?
    /// The folder herdr starts its shell in, known before herdr answers: the split pane's or the new tab's, as herdr
    /// picks it with its default `new_cwd` (`resolve_new_terminal_cwd`, src/app/creation.rs), then herdr's answer's.
    /// From the snapshot, which a `cd` since herdr's last report does not change: herdr's answer corrects it.
    var cwd: String?
    /// Its folder line is a field.
    var editing = false
    /// The `cd` to its folder, typed before the picked shell or agent runs, as Go to Directory types it.
    var cdCommand: String? {
        folder.map { "cd -- " + $0.shellQuoted }
    }

    init(standIn: String? = nil, cwd: String? = nil) {
        self.standIn = standIn
        self.cwd = cwd
    }

    var rows: [Row] {
        let agents = Self.shownAgents
        return [.terminal] + (agents.isEmpty ? [] : [.agent]) + (open ? agents : []) + Self.plugins
    }

    func made(_ pane: HerdrKit.Pane) {
        paneID = pane.id
        terminalID = pane.terminalID
        cwd = pane.cwd ?? cwd
    }

    /// Its number key: the top rows', or the agents' while Agent is open.
    func number(_ row: Row) -> Int? {
        let numbered = open ? Self.shownAgents : rows.filter { $0.agent == nil }
        return numbered.firstIndex(of: row).map { $0 + 1 }
    }
}

extension Chooser.Row {
    var agent: Chooser.Agent? {
        if case let .start(index) = self {
            Chooser.agents[index]
        } else {
            nil
        }
    }

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

    /// A chooser on a new tab's or split's stand-in, in the folder herdr will start it in; `made` gives it herdr's
    /// pane.
    func choose(standIn: String, cwd: String?) -> Chooser {
        let chooser = Chooser(standIn: standIn, cwd: cwd)
        choosers.append(chooser)
        return chooser
    }

    /// A chooser on herdr's new pane; with an agent, its loader while the agent starts.
    func choose(_ pane: HerdrKit.Pane?, starting agent: Chooser.Agent? = nil, closed: String? = nil) {
        guard let pane else { return }
        let chooser = Chooser()
        chooser.made(pane)
        choosers.append(chooser)
        if let agent {
            start(agent, chooser, closed: closed)
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

    /// ↑ ↓ move through the rows and wrap at the ends, Return picks at once, → opens Agent, ← and Esc close it, Esc on
    /// a closed list picks Terminal. The number keys pick the top rows, or the agents while Agent is open. Other keys
    /// do nothing, also while the loader shows.
    func key(_ event: NSEvent, _ chooser: Chooser, page: Page?) {
        // A held key moves on, but picks once: a held 2 would open Agent, then start Codex.
        guard chooser.starting == nil, chooser.opening == nil,
              !event.isARepeat || [125, 126].contains(event.keyCode) else { return }
        let installed = page?.terminals.pages?.agents
        let rows = chooser.rows.filter { !Chooser.missing($0, installed) },
            index = rows.firstIndex(of: chooser.selected) ?? 0
        switch event.keyCode {
        case 125, 126: chooser.selected = rows[(index + (event.keyCode == 125 ? 1 : rows.count - 1)) % rows.count]
        // → on a closed Agent opens it; ← and Esc close an open one.
        case 124 where chooser.selected == .agent && !chooser.open, 123 where chooser.open, 53 where chooser.open:
            pick(chooser, .agent, page: page)
        case 53: pick(chooser, .terminal, page: page)
        case 48: chooser.editing = true
        case 36 where rows.contains(chooser.selected), 76 where rows.contains(chooser.selected):
            pick(chooser, chooser.selected, page: page)
        default:
            let number = Int(event.charactersIgnoringModifiers ?? "")
            if let row = rows.first(where: { number != nil && chooser.number($0) == number }) {
                pick(chooser, row, page: page)
            }
        }
    }

    /// Agent opens with its first installed agent selected, or closes with itself selected. `page`: where it was
    /// picked.
    func pick(_ chooser: Chooser, _ row: Chooser.Row, page: Page?) {
        switch row {
        case .agent:
            chooser.open.toggle()
            let installed = page?.terminals.pages?.agents
            chooser.selected = chooser.open
                ? Chooser.shownAgents.first { !Chooser.missing($0, installed) } ?? .agent
                : .agent
        case let .start(index): start(Chooser.agents[index], chooser)
        case let .plugin(id):
            if let plugin = Registry.plugin(id) {
                page?.open(plugin, chooser)
            }
        case .terminal:
            if let command = chooser.cdCommand, let id = chooser.paneID {
                Task { await write { try await $0.sendInput(command, keys: ["enter"], pane: id) } }
            }
            drop(chooser)
        }
    }

    /// Types the agent's command (with Ovvi's chat flags, ui/chat-view#launch-flags) into the pane's shell,
    /// as Go to Directory types its `cd`, and shows the loader until the agent is ready: herdr reports it with a status
    /// (all four agents, read from their screens on any machine).
    /// The terminal shows sooner when the shell is in front again (the command failed or ended), or after 10 s.
    /// `resume`: Relaunch with Chat's session; the agent in the pane quits first. `closed`: a closed session's
    /// (Archived's Resume), in this new pane.
    func start(_ agent: Chooser.Agent, _ chooser: Chooser, resume: String? = nil, closed: String? = nil) {
        // Once: a double click's second click lands on the row as it fades out.
        guard chooser.starting == nil else { return }
        chooser.starting = agent
        Task {
            defer { drop(chooser) }
            let resumed = await resumed(agent, chooser, resume: resume, closed: closed)
            guard resume ?? closed == nil || resumed != nil else { return }
            let clock = ContinuousClock(), begun = clock.now
            var sent: ContinuousClock.Instant?, shells = 0, line: String?
            // A new tab's stand-in waits for herdr's pane. A chooser dropped meanwhile (its pane closed) ends it.
            while clock.now - begun < .seconds(10), choosers.contains(where: { $0 === chooser }) {
                if let client, let id = chooser.paneID {
                    guard let since = sent else {
                        // With Ovvi's flags first; once more without them when the shell came back at once (a build
                        // that refuses them starts with no chat rather than not at all).
                        let next = line == nil
                            ? await [chooser.cdCommand, firstLine(agent, resumed)].compactMap(\.self)
                            .joined(separator: " && ")
                            : agent.command
                        // Its pane may have closed during the launch's run on the machine.
                        guard choosers.contains(where: { $0 === chooser }),
                              await (try? client.sendInput(next, keys: ["enter"], pane: id)) != nil
                        else {
                            return
                        }
                        line = next
                        sent = clock.now
                        chooser.typed = true
                        opensOnChat(id)
                        continue
                    }
                    if let pane = try? await client.pane(id), pane.agent != nil,
                       pane.agentStatus.map({ $0 != .unknown }) == true
                    {
                        // Again: a new tab's pane may have been missing from the snapshot as its line went in.
                        opensOnChat(id)
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
                            guard line != agent.command, resume ?? closed == nil else { return }
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
    /// A new agent's card opens on its chat when Settings ▸ Agents says so, as after Relaunch with Chat. Set as its
    /// line goes in: no card makes the chat while the chooser is there.
    private func opensOnChat(_ paneID: String) {
        if AppSettings().agentView == .chat {
            pane(paneID)?.relaunched = true
        }
    }
}

extension WindowPages {
    /// The window's one check for the agents on its machine (ui/new-pane#agent), in its login shell so its `PATH` and
    /// aliases count. Kept for the window's life: a new window sees an agent installed since. One that failed (a
    /// remote machine not connected yet, a shell that cannot run the loop) is asked again when the window connects.
    func findAgents() {
        guard agents == nil else { return }
        let commands = Chooser.agents.map(\.command)
        // The first `echo`: a startup file's text with no final newline would join the first agent's line. The end
        // marker: a shell that ran the loop.
        let script = "echo; for c in \(commands.joined(separator: " ")); do command -v $c >/dev/null && echo $c; done; "
            + "echo ovvi-end"
        Task {
            let lines = try? await machine.exec().output(["sh", "-c", #"exec "${SHELL:-sh}" -ilc "$1""#, "sh",
                                                          script], timeout: .seconds(3))
                .split(separator: "\n").map(String.init)
            if let lines, lines.last == "ovvi-end" {
                agents = Set(lines).intersection(commands)
            }
        }
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

    /// The keyboard card's chooser takes its keys before the terminal under it (`OvviApp`), in the key window (a
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
