import AppKit
import HerdrKit
import Observation

/// The live model of one herdr session. Snapshots land on stable objects keyed by id; Observation
/// skips fields that did not change, so one status change redraws one row (design D6). The selection is the
/// window's (`Page`).
@MainActor @Observable
final class HostStore {
    enum State: Equatable {
        case connecting, live
        case failed(HerdrError)
    }

    let session: String
    /// An edit changes its name and icon (`MachineList.save`).
    var machine: Machine
    private(set) var state = State.connecting
    /// Every session herdr knows on the machine.
    private(set) var sessions: [Session] = []
    private(set) var workspaces: [Workspace] = []
    private(set) var panes: [Pane] = []
    /// Each tab's panes in herdr's order, set only when it changes: a view of one tab reads its own.
    private(set) var tabPanes: [String: [Pane]] = [:]
    /// Its panes that need you.
    private(set) var waiting = 0
    /// Its panes whose finish is not seen yet.
    private(set) var done = 0
    /// herdr's focused workspace: a page's first selection.
    private(set) var focusedWorkspaceID: String?
    /// The last failed write, shown for a few seconds; ✕ clears it.
    var notice: Notice?
    /// The card whose border flashes now (`ovvi reveal`).
    var flashing: String?
    /// New panes' choosers (ui/new-pane) and agent panes' chats by terminal id: the app's own, for every window.
    var choosers: [Chooser] = []
    @ObservationIgnored var chats: [String: Chat] = [:]
    /// Writes, one at a time in order: a quick second close or split waits for the first (both show at once).
    @ObservationIgnored let writes = Gate(1)
    /// A write in flight (not observed: read when a key or a drag acts).
    var writing: Bool {
        writes.busy
    }

    /// What shows before herdr has it.
    @ObservationIgnored var ahead = Ahead()
    /// The last snapshot, drawn again with `ahead`.
    @ObservationIgnored private(set) var last: Snapshot?
    /// Panes being closed (`Ahead`), kept with what was asked of them in case the close comes back. A closing card
    /// fades out with its header, not a stand-in's "terminal".
    @ObservationIgnored private(set) var parked: [String: Pane] = [:]
    /// The tab the user looks at (D14): selected on the page in view of the key window. Its notifications go.
    @ObservationIgnored var lookingTabID: String?
    /// The pane the user looks at (D14), as `Seen` keys it (its terminal: a moved pane stays looked at): the keyboard
    /// card on the page in view of the last key window, or a key floating window's pane; kept while the app is in the
    /// background. Its finish counts as seen once it is another pane (`Seen`).
    @ObservationIgnored private var lookingKey: String? {
        didSet {
            if lookingKey != oldValue {
                seen.look(looking)
                showStates()
            }
        }
    }

    /// The windows that have its page open, the controller first (D66): the window where the user last typed or
    /// clicked in a card of the session. The others watch.
    var windows: [WindowPages] = []
    /// Its panes marked as shown (`markShown`), and the marks in flight.
    @ObservationIgnored var marked: Set<String> = []
    /// Its workspaces marked `ovvi-open`.
    @ObservationIgnored var openMarked: Set<String> = []
    @ObservationIgnored var marking: Task<Void, Never>?
    /// The session's page is in view in a visible window: git status runs only then (D67).
    var showsGit: Bool {
        windows.contains { $0.visible && $0.current?.store === self }
    }

    /// `connect` runs, and how many began: an error from before it, whose session list waited for its start, does
    /// not show.
    @ObservationIgnored private var connecting = false
    @ObservationIgnored private var connects = 0
    @ObservationIgnored private(set) var client: (any Multiplexer)?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Workspaces with a git run in flight: one at a time each.
    @ObservationIgnored var gitRuns: Set<String> = []
    /// Program asks in flight, 8 at most: a 600-pane session's first snapshot made 600 herdr runs.
    @ObservationIgnored let asks = Gate(8)
    @ObservationIgnored private var seen: Seen
    /// The Agents view's settles by hand, by `Pane.settleKey`; each ends at the agent's next change of state.
    var settles: [String: AgentSettle] = [:]
    /// `seen`'s marks as last kept in the defaults (`keepMarks`).
    @ObservationIgnored private var marks: [String: Seen.Mark]

    private init(session: String, machine: Machine) {
        self.session = session
        self.machine = machine
        let saved = UserDefaults.agents.data(forKey: Self.marksKey(session, machine))
        marks = saved.flatMap { try? JSONDecoder().decode([String: Seen.Mark].self, from: $0) } ?? [:]
        seen = Seen(marks: marks)
    }

    /// The app's stores, one per machine and session open in a window (design D43). A session with no page has none.
    private static var open: [String: HostStore] = [:]

    static func key(_ session: String, _ machine: Machine) -> String {
        "\(machine.id) \(session)"
    }

    /// Every open session's store, each once however many windows show it.
    static var all: [HostStore] {
        open.values.sorted { $0.session < $1.session }
    }

    /// The session's store, made and connected on first use; `start` starts its server first (stopped or new).
    static func named(_ session: String, on machine: Machine, start: Bool = false) -> HostStore {
        if let store = open[key(session, machine)] {
            return store
        }
        let store = HostStore(session: session, machine: machine)
        open[key(session, machine)] = store
        store.task = Task { await store.run(start: start) }
        return store
    }

    /// Its page closed: the events stream and every herdr run of it end; the session keeps running.
    func disconnect() {
        task?.cancel()
        Self.open[Self.key(session, machine)] = nil
    }

    /// The Connect button and a new machine: connects to the remote machine, asking the user what ssh asks in the
    /// window that connects (machines#health-check: only this may prompt). The page shows Connecting from the click
    /// until the session answers.
    func connect(in pages: WindowPages) async {
        // A second click joins the first.
        guard machine.isRemote, !connecting else { return }
        connecting = true
        connects += 1
        if case .failed = state {
            state = .connecting
        }
        var failure: Error?
        do {
            try await (machine.exec() as? SSHExec)?.connect { question in await pages.ask(question) }
        } catch HerdrError.disconnected {
            // The Disconnected page says it.
        } catch {
            failure = error
        }
        connecting = false
        // Its first check failed when the machine was not connected yet.
        pages.findAgents()
        // The read's answer ends Connecting now; the notice's 4 s do not hold it.
        await client?.refresh()
        if let failure {
            await show(Notice(text: failure.localizedDescription))
        }
    }

    /// Follows the session until the task is cancelled. A failed start says why, then connects anyway: the page
    /// shows "not running" with Start.
    private func run(start: Bool) async {
        if start {
            do {
                try await Self.start(session, on: machine)
            } catch {
                // Kept until the session answers.
                notice = Notice(text: error.localizedDescription)
            }
        }
        let client: any Multiplexer = await HerdrClient(session: session, exec: machine.exec())
        self.client = client
        defer { self.client = nil }
        var loadedSessions = false
        for await update in await client.updates() {
            switch update {
            case let .snapshot(snapshot):
                let start = Latency.threadTime
                let changes = apply(snapshot)
                state = .live
                snapshotted(changes)
                Latency.shared.applied(since: start)
                // After the first snapshot, so the session list never delays the layout.
                if !loadedSessions {
                    loadedSessions = true
                    notice = nil
                    // State files of plugin panes closed elsewhere (plugins/api#state), and the `ovvi` command.
                    Task { [machine, session] in await machine.exec().pruneState(session: session) }
                    Task { [machine] in
                        if let script = AgentCommands.script {
                            await machine.exec().prepareAgent(script: script)
                        }
                    }
                    await loadSessions()
                }
            case let .copy(text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case let .request(id, pane):
                // ponytail: not cancelled with the store; its runs' timeouts and the float's 8 s wait end it.
                Task { await answer(request: id, from: pane) }
            case let .float(request):
                WindowPages.float(session: request.session, pane: request.pane, machine: machine.id,
                                  over: windows.first)
            case let .error(error):
                await failed(error)
            }
        }
    }

    private func failed(_ error: HerdrError) async {
        // Not while Connect runs, nor one that waited for its start: Connect's own read follows.
        let connects = connects
        guard !connecting else { return }
        // First, to tell "not running" from other failures without a flash of the other text.
        await loadSessions()
        guard connects == self.connects else { return }
        state = .failed(error)
        snapshotted([])
    }

    func panes(in tabID: String?) -> [Pane] {
        tabID.flatMap { tabPanes[$0] } ?? []
    }

    func pane(_ id: String) -> Pane? {
        panes.first { $0.id == id }
    }

    /// False only when herdr lists the session as stopped (or not at all).
    var isRunning: Bool {
        sessions.isEmpty || sessions.contains { $0.name == session && $0.running }
    }

    /// herdr's session list again: a session started since shows up.
    func loadSessions() async {
        guard let client else { return }
        sessions = await (try? client.sessions()) ?? sessions
    }

    /// The last snapshot drawn again, with what the app shows ahead of herdr.
    func redraw() {
        if let last {
            snapshotted(apply(last))
        }
    }

    /// The snapshot onto the objects, as the app shows it (`ahead`); its agent changes.
    private func apply(_ snapshot: Snapshot) -> [Seen.Change] {
        // A pane closed at its chooser or chat: herdr's raw panes, so one made since the last snapshot stays.
        let gone = Set(last?.panes.compactMap(\.terminalID) ?? []).subtracting(snapshot.panes.compactMap(\.terminalID))
        drop(closed: gone)
        last = snapshot
        let shown = ahead.show(snapshot)
        let tabs = Dictionary(grouping: shown.tabs, by: \.workspaceID)
        reuse(self, \.workspaces, shown.workspaces, Workspace.init(id:)) { workspace, new in
            workspace.label = new.label
            workspace.activeTabID = new.activeTabID
            workspace.worktree = new.worktree
            reuse(workspace, \.tabs, tabs[new.id] ?? [], Tab.init(id:)) { tab, new in
                tab.label = new.label
                tab.tree = shown.trees[new.id]
            }
        }
        focusedWorkspaceID = snapshot.focusedWorkspaceID
        let herdrs = Set(snapshot.panes.map(\.id))
        parked = parked.filter { herdrs.contains($0.key) }
        for pane in panes where ahead.closing.contains(pane.id) {
            parked[pane.id] = pane
        }
        let make = { self.parked.removeValue(forKey: $0) ?? Pane(id: $0) }
        // Once, not a new set for each pane: O(panes × tabs) per snapshot.
        let focused = snapshot.focusedPaneIDs
        reuse(self, \.panes, shown.panes, make) { pane, new in
            watchProgram(pane, new)
            remakeCard(pane, new)
            pane.agent = new.agent
            pane.terminalTitle = new.title
            pane.label = new.label
            pane.cwd = new.cwd
            pane.focused = focused.contains(new.id)
            pane.tabID = new.tabID
            pane.terminalID = new.terminalID
        }
        let grouped = Dictionary(grouping: panes, by: \.tabID)
        if grouped.mapValues({ $0.map(\.id) }) != tabPanes.mapValues({ $0.map(\.id) }) {
            tabPanes = grouped
        }
        let agents = Dictionary(snapshot.agents.map { ($0.paneID, $0) }, uniquingKeysWith: { first, _ in first })
        for pane in panes {
            pane.agentName = agents[pane.id].flatMap { $0.displayAgent ?? $0.agent }
            pane.changeSeq = agents[pane.id]?.stateChangeSeq
        }
        let changes = seen.update(snapshot.agents, looking: looking)
        showStates()
        closeArrived()
        Task { await updateGit(all: false) }
        return changes
    }

    /// Each workspace's branch (D67): `all` for the 10 s refresh, else only a workspace that is new or whose root
    /// changed. Only while the page is in view.
    func updateGit(all: Bool) async {
        guard showsGit, await gitUsable.value else { return }
        for workspace in workspaces {
            // The page left view (or closed) during the runs before.
            guard showsGit, !Task.isCancelled else { return }
            let root = root(of: workspace)
            // A root that changes during a run waits for the next tick.
            guard let root, all || root != workspace.gitRoot, !gitRuns.contains(workspace.id) else { continue }
            workspace.gitRoot = root
            gitRuns.insert(workspace.id)
            // One after another: 30 workspaces are not 30 git processes at once.
            workspace.git = await GitStatus.of(root, exec: machine.exec())
            gitRuns.remove(workspace.id)
        }
    }
}

extension HostStore {
    private var looking: Set<String> {
        Set([lookingKey].compactMap(\.self))
    }

    private func showStates() {
        for pane in panes {
            let key = Seen.key(terminalID: pane.terminalID, paneID: pane.id)
            pane.state = seen.states[key]
            pane.since = seen.since[key]
        }
        showStrongest()
        keepMarks()
        keepPins()
        let kept = settles.filter { key, settle in panes.contains { $0.settleKey == key && $0.since == settle.since } }
        if kept != settles {
            settles = kept
        }
    }

    /// Each tab's strongest agent, each workspace's state and the panes that need you or are done, kept here: views
    /// that read every pane's state for them drew again on any agent's change, every capsule and sidebar row.
    private func showStrongest() {
        for workspace in workspaces {
            for tab in workspace.tabs {
                let tabAgents = panes(in: tab.id).filter { $0.state != nil }
                let strongest = tabAgents.max { $0.state ?? .idle < $1.state ?? .idle }
                // Observation skips an equal value, but not an identical object.
                if tab.agent !== strongest {
                    tab.agent = strongest
                }
            }
            workspace.state = workspace.tabs.compactMap { $0.agent?.state }.max()
        }
        waiting = panes.count { $0.state == .needsYou }
        done = panes.count { $0.state == .finishedUnseen }
    }

    /// Where `seen`'s marks are kept, so an idle agent's time outlives a relaunch (Settled).
    private static func marksKey(_ session: String, _ machine: Machine) -> String {
        "agentMarks.\(machine.id) \(session)"
    }

    /// Keeps `seen`'s marks once a snapshot came: before it they are empty.
    private func keepMarks() {
        guard last != nil, seen.marks != marks else { return }
        marks = seen.marks
        let key = Self.marksKey(session, machine)
        if marks.isEmpty {
            UserDefaults.agents.removeObject(forKey: key)
        } else {
            UserDefaults.agents.set(try? JSONEncoder().encode(marks), forKey: key)
        }
    }

    /// The user looks at `pane` of `store` (a key window's), and at nothing in the other sessions.
    static func look(_ pane: Pane?, in store: HostStore) {
        let key = pane.map { Seen.key(terminalID: $0.terminalID, paneID: $0.id) }
        for other in all {
            other.lookingKey = other === store ? key : nil
        }
    }
}

/// This Mac's, for the app's life: it reads the login shell's environment once.
let localExec = Task { await ProcessExec() }
/// Checked once at launch, so the developer tools dialog never opens.
/// ponytail: This Mac's check, for remote machines' git too; ask each machine when one lacks git.
let gitUsable = Task { await GitStatus.usable(exec: localExec.value) }
