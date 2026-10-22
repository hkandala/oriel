import Foundation
import HerdrKit
import Observation

/// The live model of one herdr session. Snapshots land on stable objects keyed by id; Observation
/// skips fields that did not change, so one status change redraws one row (design D6).
@MainActor @Observable
final class HostStore {
    enum State: Equatable {
        case connecting, live
        case failed(HerdrError)
    }

    /// A close waiting for the user's yes (design D41).
    enum Close {
        /// The pane and the program running in it.
        case pane(String, program: String)
        case tab(String)

        var isTab: Bool {
            if case .tab = self {
                true
            } else {
                false
            }
        }
    }

    let session: String
    /// Start the session's server first: it is stopped or new.
    private let start: Bool
    private(set) var state = State.connecting
    /// Every session herdr knows on this Mac, for the session picker.
    private(set) var sessions: [Session] = []
    private(set) var workspaces: [Workspace] = []
    private(set) var panes: [Pane] = []
    var selectedWorkspaceID: String?
    /// The strip's scroll offset in pages (1.5 = halfway from the second tab to the third), for the tab marker. One
    /// strip shows every workspace, so one number.
    var page = 0.0
    /// The last failed write, shown for a few seconds.
    private(set) var notice: String?
    /// A write in flight; the buttons wait for it.
    private(set) var writing = false
    var closing: Close?
    /// The app's own zoom (design D11): this card fills its tab's page.
    var zoomedPaneID: String?
    /// A tab this app just made, selected once a snapshot shows it.
    @ObservationIgnored private var arriving: String?
    @ObservationIgnored private var client: (any Multiplexer)?
    #if os(macOS)
        let terminals = PaneViewRegistry()
        /// The tab whose terminal last got the keyboard from the app.
        @ObservationIgnored private var keyboardTabID: String?
        /// The terminal that last had the keyboard in each tab: the app's own, like the selection. Observed: the
        /// tab's icon stack puts it in front.
        private var keyboardTerminals: [String: String] = [:]
    #endif

    init(session: String, start: Bool = false) {
        self.session = session
        self.start = start
        #if os(macOS)
            terminals.onKeyboard = { [weak self] terminalID in
                guard let self, let tabID = panes.first(where: { $0.terminalID == terminalID })?.tabID else { return }
                keyboardTerminals[tabID] = terminalID
            }
            // Return may have started or ended a program.
            terminals.onReturn = { [weak self] terminalID in
                guard let self, let pane = panes.first(where: { $0.terminalID == terminalID }) else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    await askProgram(pane.id)
                }
            }
        #endif
    }

    /// "This Mac" for the default session, "This Mac · ‹session›" for the others.
    static func name(_ session: String) -> String {
        session == "default" ? "This Mac" : "This Mac · \(session)"
    }

    func pane(_ id: String) -> Pane? {
        panes.first { $0.id == id }
    }

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedTab: Tab? {
        selectedWorkspace.flatMap { workspace in workspace.tabs.first { $0.id == workspace.selectedTabID } }
    }

    /// Selects the tab before or after the selected one, round the ends.
    func step(_ offset: Int) {
        guard let workspace = selectedWorkspace, !workspace.tabs.isEmpty else { return }
        let tabs = workspace.tabs
        let index = tabs.firstIndex { $0.id == workspace.selectedTabID } ?? 0
        workspace.selectedTabID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    /// The tab's panes for its icon stack, at most 5: the keyboard card's first (herdr's focused pane until one
    /// had the keyboard), then herdr's order.
    func stack(_ tab: Tab) -> [Pane] {
        let tabPanes = panes.filter { $0.tabID == tab.id }
        #if os(macOS)
            let keyboard = keyboardTerminals[tab.id]
            let front = tabPanes.first { $0.terminalID != nil && $0.terminalID == keyboard }
                ?? tabPanes.first(where: \.focused)
        #else
            let front = tabPanes.first(where: \.focused)
        #endif
        return Array(([front].compactMap(\.self) + tabPanes.filter { $0 !== front }).prefix(5))
    }

    /// The card keys go to: the terminal with the keyboard, else herdr's focused pane of the selected tab.
    var keyboardPane: Pane? {
        #if os(macOS)
            if let id = terminals.keyboardPaneID, let pane = pane(id) {
                return pane
            }
        #endif
        return panes.first { $0.tabID == selectedTab?.id && $0.focused }
    }

    /// The selected tab's terminals (terminal id → pane id): the ones that stream.
    var shownTerminals: [String: String] {
        Dictionary(panes.compactMap { pane in
            pane.tabID == selectedTab?.id ? pane.terminalID.map { ($0, pane.id) } : nil
        }, uniquingKeysWith: { first, _ in first })
    }

    #if os(macOS)
        /// Streams the selected tab's terminals (see the registry), drops those of closed panes.
        func showTerminals() {
            let alive = Set(panes.compactMap(\.terminalID))
            terminals.show(shownTerminals, alive: alive)
            // A newly selected tab gives the keyboard back to the card it had; herdr's focused pane
            // only picks it the first time a tab is shown. Later snapshots leave it alone, unless the
            // card with the keyboard closed: then the tab's next card takes it.
            if let tab = selectedTab, let gone = keyboardTerminals[tab.id], !alive.contains(gone) {
                keyboardTerminals[tab.id] = nil
                focusKeyboardCard()
            } else if selectedTab?.id != keyboardTabID {
                focusKeyboardCard()
            }
        }

        /// Gives the keyboard to the selected tab's card: the one it last had, else herdr's focused pane.
        func focusKeyboardCard() {
            guard let tab = selectedTab else { return }
            let tabPanes = panes.filter { $0.tabID == tab.id && $0.terminalID != nil }
            let pane = tabPanes.first { $0.terminalID == keyboardTerminals[tab.id] }
                ?? tabPanes.first(where: \.focused) ?? tabPanes.first
            if let pane, let terminalID = pane.terminalID {
                keyboardTabID = tab.id
                // Made now if its card has not drawn yet (a tab just jumped to); it takes the keyboard once it is in
                // the window.
                _ = terminals.terminal(terminalID, pane: pane.id)
                terminals.focus(terminalID)
            }
        }
    #endif

    /// False only when herdr lists the session as stopped (or not at all).
    var isRunning: Bool {
        sessions.isEmpty || sessions.contains { $0.name == session && $0.running }
    }

    /// Follows the session until the calling task is cancelled.
    func run(exec: any Exec) async {
        var loadedSessions = false
        do {
            // herdr is the only multiplexer (design D49).
            let client: any Multiplexer = HerdrClient(session: session, exec: exec)
            self.client = client
            defer { self.client = nil }
            #if os(macOS)
                if start {
                    try await client.startServer()
                    // A new server has no workspace yet.
                    if try await client.snapshot().workspaces.isEmpty {
                        _ = try await client.newWorkspace(cwd: NSHomeDirectory())
                    }
                }
                terminals.client = client
                defer { terminals.closeAll() }
            #endif
            for await update in await client.updates() {
                switch update {
                case let .snapshot(snapshot):
                    apply(snapshot)
                    #if os(macOS)
                        // Also retries a terminal whose stream failed.
                        showTerminals()
                    #endif
                    state = .live
                    // After the first snapshot, so the picker never delays the layout.
                    if !loadedSessions {
                        loadedSessions = true
                        await loadSessions()
                    }
                case let .error(error):
                    // First, to tell "not running" from other failures without a flash of the other text.
                    await loadSessions()
                    state = .failed(error)
                }
            }
        } catch {
            state = .failed(error as? HerdrError ?? .failed("\(error)"))
        }
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
            if pane.program == nil {
                pane.asked = false
            }
        }
    }

    /// herdr's session list again, for the picker: a session started since shows up.
    func loadSessions() async {
        guard let client else { return }
        sessions = await (try? client.sessions()) ?? sessions
    }

    private func apply(_ snapshot: Snapshot) {
        let tabs = Dictionary(grouping: snapshot.tabs, by: \.workspaceID)
        reuse(self, \.workspaces, snapshot.workspaces, Workspace.init(id:)) { workspace, new in
            workspace.label = new.label
            workspace.status = new.agentStatus
            reuse(workspace, \.tabs, tabs[new.id] ?? [], Tab.init(id:)) { tab, new in
                tab.label = new.label
                tab.status = new.agentStatus
                tab.tree = snapshot.trees[new.id]
            }
            if !workspace.tabs.contains(where: { $0.id == workspace.selectedTabID }) {
                workspace.selectedTabID = workspace.tabs.contains { $0.id == new.activeTabID }
                    ? new.activeTabID : workspace.tabs.first?.id
            }
        }
        let focused = snapshot.focusedPaneIDs
        reuse(self, \.panes, snapshot.panes, Pane.init(id:)) { pane, new in
            // Another terminal (herdr reused the id), agent or title word: the program may have changed. A progress
            // title ("build 51%") changes on and on; its first word does not.
            let reused = new.terminalID != pane.terminalID
            if reused {
                pane.program = nil
            }
            let word = { (title: String?) in title?.split(separator: " ").first }
            if pane.asked, reused || new.agent != pane.agent || word(new.title) != word(pane.terminalTitle) {
                Task { await askProgram(pane.id) }
            }
            pane.agent = new.agent
            pane.terminalTitle = new.title
            pane.label = new.label
            pane.cwd = new.cwd
            pane.focused = focused.contains(new.id)
            pane.tabID = new.tabID
            pane.terminalID = new.terminalID
        }
        if let id = zoomedPaneID, pane(id) == nil {
            zoomedPaneID = nil
        }
        if let id = arriving, let workspace = workspaces.first(where: { $0.tabs.contains { $0.id == id } }) {
            arriving = nil
            selectedWorkspaceID = workspace.id
            workspace.selectedTabID = id
        }
        if selectedWorkspace == nil {
            selectedWorkspaceID = workspaces.contains { $0.id == snapshot.focusedWorkspaceID }
                ? snapshot.focusedWorkspaceID : workspaces.first?.id
        }
    }
}

/// Writes: each is one multiplexer action, then a snapshot read.
extension HostStore {
    /// A split restores a zoomed layout first, as tmux does: the new pane shows.
    func split(_ paneID: String, _ direction: SplitNode.Direction) async {
        zoomedPaneID = nil
        await write { try await $0.split(paneID, direction) }
    }

    /// A new tab in the selected workspace, in the keyboard card's directory; the snapshot after it selects it.
    func newTab() async {
        guard let workspace = selectedWorkspace else { return }
        var cwd = keyboardPane?.cwd
        // Asked now: a `cd` sends no event, so the snapshot's cwd may be old.
        if let pane = keyboardPane, let fresh = try? await client?.pane(pane.id).cwd {
            cwd = fresh
        }
        await write {
            arriving = try await $0.newTab(workspace: workspace.id, cwd: cwd ?? NSHomeDirectory()) ?? arriving
        }
    }

    /// The snapshot after it selects the new workspace (`arriving`).
    func newWorkspace() async {
        await write { arriving = try await $0.newWorkspace(cwd: NSHomeDirectory()) ?? arriving }
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
        }
    }

    /// Zooms the card, or restores the layout when it is the zoomed one. The zoomed card gets the keyboard.
    func zoom(_ paneID: String) {
        zoomedPaneID = zoomedPaneID == paneID ? nil : paneID
        #if os(macOS)
            if zoomedPaneID != nil, let terminalID = pane(paneID)?.terminalID {
                terminals.focus(terminalID)
            }
        #endif
    }

    /// One write. No focus change; the snapshot after it draws the result.
    private func write(_ action: (any Multiplexer) async throws -> Void) async {
        guard let client else { return }
        guard !writing else {
            // A confirmed close must not vanish silently.
            await show("Busy, try again")
            return
        }
        writing = true
        notice = nil
        do {
            try await action(client)
            writing = false
            await client.refresh()
        } catch {
            writing = false
            await show(error.localizedDescription)
        }
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

/// Keeps the object of each id that stays, makes the new ones, and replaces the list only when its
/// ids changed, so views of the list redraw only then.
@MainActor
private func reuse<Owner: AnyObject, Object: Identifiable<String>, Item: Identifiable<String>>(
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
