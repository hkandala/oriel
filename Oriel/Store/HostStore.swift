import Foundation
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
    private(set) var state = State.connecting
    /// Every session herdr knows on this Mac.
    private(set) var sessions: [Session] = []
    private(set) var workspaces: [Workspace] = []
    private(set) var panes: [Pane] = []
    /// herdr's focused workspace: a page's first selection.
    private(set) var focusedWorkspaceID: String?
    /// The last failed write, shown for a few seconds.
    private(set) var notice: String?
    /// A write in flight; the buttons wait for it.
    private(set) var writing = false
    var closing: Close?
    /// Set while the session's page is in view in a visible window: git status runs only then (D67).
    var showsGit = false

    /// The tab the user looks at (D14): selected on the page in view of the key window. Its finishes are seen.
    @ObservationIgnored var lookingTabID: String? {
        didSet {
            if lookingTabID != oldValue {
                seen.look(looking)
                showStates()
            }
        }
    }

    #if os(macOS)
        /// The windows that have its page open, the controller first (D66): the window where the user last typed or
        /// clicked in a card of the session. The others watch.
        var windows: [WindowPages] = []
    #endif
    @ObservationIgnored private(set) var client: (any Multiplexer)?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Workspaces with a git run in flight: one at a time each.
    @ObservationIgnored private var gitRuns: Set<String> = []
    @ObservationIgnored private var seen = Seen()

    private init(session: String) {
        self.session = session
    }

    /// The app's stores, one per session open in a window (design D43). A session with no page has none.
    private static var open: [String: HostStore] = [:]

    /// Every open session's store, each once however many windows show it.
    static var all: [HostStore] {
        open.values.sorted { $0.session < $1.session }
    }

    #if os(macOS)
        /// The session's store, made and connected on first use; `start` starts its server first (stopped or new).
        static func named(_ session: String, start: Bool = false) -> HostStore {
            if let store = open[session] {
                return store
            }
            let store = HostStore(session: session)
            open[session] = store
            store.task = Task { await store.run(start: start) }
            return store
        }

        /// Its page closed: the events stream and every herdr run of it end; the session keeps running.
        func disconnect() {
            task?.cancel()
            // Also ends a git loop already running for it.
            showsGit = false
            Self.open[session] = nil
        }

        /// Starts the session's server when it is not running (a launchd job, D47); a server started here gets
        /// its first workspace in home, as a new one has none.
        static func start(_ session: String) async throws {
            // herdr is the only multiplexer (design D49).
            let client: any Multiplexer = await HerdrClient(session: session, exec: exec.value)
            if try await client.startServer(), try await client.snapshot().workspaces.isEmpty {
                _ = try await client.newWorkspace(label: nil, cwd: NSHomeDirectory())
            }
        }

        /// The Start button of a session that stopped: the running store finds it again.
        func start() async {
            do {
                try await Self.start(session)
                await client?.refresh()
            } catch {
                await show(error.localizedDescription)
            }
        }

        /// Follows the session until the task is cancelled. A failed start says why, then connects anyway: the page
        /// shows "not running" with Start.
        private func run(start: Bool) async {
            if start {
                do {
                    try await Self.start(session)
                } catch {
                    // Kept until the session answers.
                    notice = error.localizedDescription
                }
            }
            let client: any Multiplexer = await HerdrClient(session: session, exec: exec.value)
            self.client = client
            defer { self.client = nil }
            var loadedSessions = false
            for await update in await client.updates() {
                switch update {
                case let .snapshot(snapshot):
                    let changes = apply(snapshot)
                    state = .live
                    snapshotted(changes)
                    // After the first snapshot, so the session list never delays the layout.
                    if !loadedSessions {
                        loadedSessions = true
                        notice = nil
                        await loadSessions()
                    }
                case let .error(error):
                    // First, to tell "not running" from other failures without a flash of the other text.
                    await loadSessions()
                    state = .failed(error)
                    snapshotted([])
                }
            }
        }
    #endif

    func pane(_ id: String) -> Pane? {
        panes.first { $0.id == id }
    }

    /// False only when herdr lists the session as stopped (or not at all).
    var isRunning: Bool {
        sessions.isEmpty || sessions.contains { $0.name == session && $0.running }
    }

    /// One `pane.process_info`; the icon follows. Only the latest ask lands; a failed first one is made again.
    func askProgram(_ paneID: String) async {
        guard let client, let pane = pane(paneID) else { return }
        pane.asked = true
        pane.asks += 1
        let ask = pane.asks
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

    /// herdr's session list again: a session started since shows up.
    func loadSessions() async {
        guard let client else { return }
        sessions = await (try? client.sessions()) ?? sessions
    }

    /// The panes of the tab the user looks at, as `Seen` keys them.
    private var looking: Set<String> {
        Set(panes.filter { $0.tabID == lookingTabID }.map { Seen.key(terminalID: $0.terminalID, paneID: $0.id) })
    }

    /// Each pane's agent state from the ledger.
    private func showStates() {
        for pane in panes {
            let key = Seen.key(terminalID: pane.terminalID, paneID: pane.id)
            pane.state = seen.states[key]
            pane.since = seen.since[key]
        }
    }

    /// The snapshot onto the objects; its agent changes.
    private func apply(_ snapshot: Snapshot) -> [Seen.Change] {
        let tabs = Dictionary(grouping: snapshot.tabs, by: \.workspaceID)
        reuse(self, \.workspaces, snapshot.workspaces, Workspace.init(id:)) { workspace, new in
            workspace.label = new.label
            workspace.activeTabID = new.activeTabID
            workspace.worktree = new.worktree
            reuse(workspace, \.tabs, tabs[new.id] ?? [], Tab.init(id:)) { tab, new in
                tab.label = new.label
                tab.tree = snapshot.trees[new.id]
            }
        }
        focusedWorkspaceID = snapshot.focusedWorkspaceID
        reuse(self, \.panes, snapshot.panes, Pane.init(id:)) { pane, new in
            watchProgram(pane, new)
            pane.agent = new.agent
            pane.terminalTitle = new.title
            pane.label = new.label
            pane.cwd = new.cwd
            pane.focused = snapshot.focusedPaneIDs.contains(new.id)
            pane.tabID = new.tabID
            pane.terminalID = new.terminalID
        }
        let agents = Dictionary(snapshot.agents.map { ($0.paneID, $0) }, uniquingKeysWith: { first, _ in first })
        for pane in panes {
            pane.agentName = agents[pane.id].flatMap { $0.displayAgent ?? $0.agent }
        }
        let changes = seen.update(snapshot.agents, looking: looking)
        showStates()
        Task { await updateGit(all: false) }
        return changes
    }

    /// Asks what the pane runs: once when it is new, and again when another terminal (herdr reused the id), agent or
    /// title word may mean another program. A progress title ("build 51%") changes on and on; its first word does not.
    private func watchProgram(_ pane: Pane, _ new: HerdrKit.Pane) {
        let reused = new.terminalID != pane.terminalID
        if reused {
            pane.program = nil
        }
        let word = { (title: String?) in title?.split(separator: " ").first }
        if pane.asked, reused || new.agent != pane.agent || word(new.title) != word(pane.terminalTitle) {
            Task { await askProgram(pane.id) }
        }
        // Every pane once, for its tab's icons, also in tabs never shown; a failed ask is made again. A second later,
        // as after Return: a new shell's startup runs short-lived programs (`sort`).
        if !pane.asked {
            pane.asked = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                await askProgram(pane.id)
            }
        }
    }

    /// Each workspace's branch (D67): `all` for the 10 s refresh, else only a workspace that is new or whose root
    /// changed. Only while the page is in view.
    func updateGit(all: Bool) async {
        #if os(macOS)
            guard showsGit, await gitUsable.value else { return }
            for workspace in workspaces {
                // The page left view (or closed) during the runs before.
                guard showsGit, !Task.isCancelled else { return }
                let root = workspace.worktree?.checkoutPath
                    ?? workspace.tabs.first.flatMap { tab in panes.first { $0.tabID == tab.id }?.cwd }
                // A root that changes during a run waits for the next tick.
                guard let root, all || root != workspace.gitRoot, !gitRuns.contains(workspace.id) else { continue }
                workspace.gitRoot = root
                gitRuns.insert(workspace.id)
                // One after another: 30 workspaces are not 30 git processes at once.
                workspace.git = await GitStatus.of(root, exec: exec.value)
                gitRuns.remove(workspace.id)
            }
        #endif
    }
}

#if os(macOS)
    /// One for the app's life: it reads the login shell's environment once.
    let exec = Task { await ProcessExec() }
    /// Checked once at launch, so the developer tools dialog never opens.
    private let gitUsable = Task { await GitStatus.usable(exec: exec.value) }
#endif

/// Writes: each is one multiplexer action, then a snapshot read.
extension HostStore {
    /// A new tab in the workspace, in `cwd` or the pane's directory, asked now: a `cd` sends no event, so the
    /// snapshot's cwd may be old. Its id.
    func newTab(in workspaceID: String, cwd: String?, of paneID: String? = nil) async -> String? {
        var cwd = cwd
        if let paneID, let fresh = try? await client?.pane(paneID).cwd {
            cwd = fresh
        }
        var created: String?
        await write { created = try await $0.newTab(workspace: workspaceID, cwd: cwd ?? NSHomeDirectory()) }
        return created
    }

    /// In home: a server launchd started has another cwd. Its first tab.
    func newWorkspace(label: String? = nil) async -> HerdrKit.Tab? {
        var created: HerdrKit.Tab?
        await write { created = try await $0.newWorkspace(label: label, cwd: NSHomeDirectory()) }
        return created
    }

    func rename(tab tabID: String, label: String) async {
        await write { try await $0.rename(tab: tabID, label: label) }
    }

    func rename(workspace workspaceID: String, label: String) async {
        await write { try await $0.rename(workspace: workspaceID, label: label) }
    }

    /// Closes a pane that runs only its shell; asks first when anything else runs (design D41).
    func close(pane paneID: String) async {
        guard let client else { return }
        let program: String?
        do {
            program = try await client.program(paneID).flatMap { $0.isShell ? nil : $0.title }
        } catch {
            // Unknown: ask.
            program = "A program"
        }
        if let program {
            closing = .pane(paneID, program: program)
        } else {
            await write { try await $0.close(pane: paneID) }
        }
    }

    /// The user said yes.
    func close(_ close: Close) async {
        switch close {
        case let .pane(id, _): await write { try await $0.close(pane: id) }
        case let .tab(id): await write { try await $0.close(tab: id) }
        case let .otherTabs(asked):
            // Not ones closed meanwhile (their close would fail the rest), and all at once: one by one, 20 tabs took
            // seconds and the bar showed each step.
            let others = asked.filter { workspace(of: $0) != nil }
            await write { client in
                try await withThrowingTaskGroup { group in
                    for other in others {
                        group.addTask { try await client.close(tab: other) }
                    }
                    try await group.waitForAll()
                }
            }
        case let .workspace(id):
            // herdr refuses to close a repository's workspace with open worktrees unless the group goes too.
            let group = workspaces.contains { $0.id == id } && !worktrees(of: id).isEmpty
            await write { try await $0.close(workspace: id, group: group) }
        }
    }

    /// One write. No focus change; the snapshot after it draws the result. Whether it went through.
    @discardableResult
    func write(_ action: (any Multiplexer) async throws -> Void) async -> Bool {
        guard let client else { return false }
        guard !writing else {
            // A confirmed close must not vanish silently.
            Task { await show("Busy, try again") }
            return false
        }
        writing = true
        notice = nil
        var failure: Error?
        do {
            try await action(client)
        } catch {
            failure = error
        }
        writing = false
        // After a failure too: part of it may have happened (Close Other Tabs).
        await client.refresh()
        if let failure {
            Task { await show(failure.localizedDescription) }
        }
        return failure == nil
    }

    /// A notice for a few seconds, unless a newer one replaced it.
    private func show(_ text: String) async {
        notice = text
        try? await Task.sleep(for: .seconds(4))
        if notice == text {
            notice = nil
        }
    }
}
