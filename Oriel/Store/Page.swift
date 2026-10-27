import AppKit
import HerdrKit
import Observation

/// One session's page in a window: its store, and the window's own selection in it (design D43). Switching
/// pages brings the selection back.
@MainActor @Observable
final class Page: Identifiable {
    let store: HostStore
    let terminals: PaneViewRegistry
    /// The app's own selection, never herdr's focus (D13).
    var selectedWorkspaceID: String? {
        didSet { newest = selectedWorkspaceID == oldValue ? newest : nil }
    }

    /// Each workspace's selected tab. Starts at herdr's active tab.
    var selectedTabIDs: [String: String] = [:] {
        didSet {
            for (workspace, tab) in oldValue where selectedTabIDs[workspace] != tab {
                // A split's newest card is no ⌘D target in another tab.
                newest = nil
                usedTabIDs[workspace, default: []].removeAll { $0 == tab }
                usedTabIDs[workspace, default: []].append(tab)
            }
        }
    }

    /// Each workspace's tabs selected before, the latest last: a closed selected tab gives way to the latest that
    /// is still there.
    @ObservationIgnored private var usedTabIDs: [String: [String]] = [:]
    /// Each workspace's tab order at the last snapshot, for the tab left of a closed one.
    @ObservationIgnored private var tabOrder: [String: [String]] = [:]
    /// The app's own zoom (design D11): this card fills its tab's page.
    var zoomedPaneID: String? {
        didSet { zoomedTabID = zoomedPaneID.flatMap(store.pane)?.tabID }
    }

    /// The zoomed card's tab when it zoomed: a move to another tab (by any window or client) ends the zoom.
    @ObservationIgnored private var zoomedTabID: String?
    /// What this window drags now; the drag source clears it when the drag ends.
    var dragging: Dragged?
    /// A close waiting for the user's yes, in this window only.
    var closing: HostStore.Closing?
    /// The floated panes (D50) by terminal id, which a move keeps, each with its Stay on Top.
    var floating: [String: Bool] = [:] {
        didSet {
            if floating.isEmpty, !oldValue.isEmpty {
                terminals.pages?.dropFloatOnly(self)
            }
        }
    }

    /// The card whose header shows the rename field.
    var renamingPaneID: String?
    /// The open find bar (⌘F), on one card.
    var find: Find?
    /// Counts ⌘F presses: each one focuses the open bar's field.
    var findFocus = 0
    /// The strip's scroll offset in pages (1.5 = halfway from the second tab to the third), for the tab marker.
    var stripPage = 0.0
    /// The terminals that had the keyboard, the latest last: each tab's keyboard card is its latest, so a closed
    /// one gives way to the card of its tab used before it. Observed: the tab's icon stack puts it in
    /// front.
    private var usedTerminals: [String] = []
    /// The latest split's card (its stand-in, then herdr's pane) until its terminal has the keyboard, and the
    /// terminal that had it before. Observed: its card is lit.
    var newest: (id: String, from: String?)?
    /// The tab whose terminal last got the keyboard from the app.
    @ObservationIgnored var keyboardTabID: String?
    /// A moved pane's terminal, which takes the keyboard once a snapshot shows it in its tab: a write does not wait
    /// for its snapshot.
    @ObservationIgnored var movedTerminal: String?
    /// A tab this page just moved a pane to or a workspace it made, selected once a snapshot shows it.
    @ObservationIgnored private var arriving: String?

    /// The session's name.
    let id: String

    init(store: HostStore, terminals: PaneViewRegistry) {
        self.store = store
        id = store.session
        self.terminals = terminals
    }

    /// Another window controls the session (D66): this page's cards watch.
    var watched: Bool {
        store.windows.first.map { $0.terminals !== terminals } ?? false
    }

    var selectedWorkspace: HostStore.Workspace? {
        store.workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedTab: HostStore.Tab? {
        selectedWorkspace.flatMap { workspace in workspace.tabs.first { $0.id == selectedTabIDs[workspace.id] } }
    }

    func select(_ workspace: HostStore.Workspace, tab tabID: String? = nil) {
        arriving = nil
        selectedWorkspaceID = workspace.id
        if let tabID {
            selectedTabIDs[workspace.id] = tabID
        }
    }

    /// After each snapshot: a closed selected tab gives way to the tab used before it, else the one to its left,
    /// else the new first; a workspace's first selection, or a saved one that is gone, is herdr's
    /// active tab. A gone workspace falls back to herdr's focused one, and a tab this page made is selected once
    /// it shows. herdr's tab takes its stand-in's place in the selection and the history.
    func settle() {
        let arrived = store.ahead.arrived
        if !arrived.isEmpty {
            usedTabIDs = usedTabIDs.mapValues { $0.map { arrived[$0] ?? $0 } }
            // Only a change: each set notifies every observer of the selection.
            let selected = selectedTabIDs.mapValues { arrived[$0] ?? $0 }
            if selected != selectedTabIDs {
                selectedTabIDs = selected
            }
        }
        for workspace in store.workspaces {
            let ids = workspace.tabs.map(\.id)
            switch selectedTabIDs[workspace.id] {
            case let selected? where ids.contains(selected):
                break
            // Known order: a close since the last snapshot. Else a saved selection gone at relaunch.
            case let gone? where tabOrder[workspace.id] != nil:
                let left = tabOrder[workspace.id]?.prefix { $0 != gone }.last(where: ids.contains)
                selectedTabIDs[workspace.id] = usedTabIDs[workspace.id]?.last(where: ids.contains) ?? left
                    ?? ids.first
            default:
                selectedTabIDs[workspace.id] = ids.contains(workspace.activeTabID) ? workspace.activeTabID
                    : ids.first
            }
            usedTabIDs[workspace.id]?.removeAll { !ids.contains($0) }
        }
        tabOrder = Dictionary(store.workspaces.map { ($0.id, $0.tabs.map(\.id)) }, uniquingKeysWith: { $1 })
        // The find bar's pane closed, or moved to another workspace (a new id).
        if let find, store.pane(find.paneID) == nil {
            self.find = nil
        }
        // A replaced pane's zoom goes to its new pane. Else gone, or alone in its tab (moved, or its neighbor closed).
        zoomReplaced()
        if let id = zoomedPaneID, alone(id) || store.pane(id)?.tabID != zoomedTabID {
            zoomedPaneID = nil
        }
        if let id = arriving, let workspace = store.workspace(of: id) {
            select(workspace, tab: id)
        }
        if selectedWorkspace == nil {
            selectedWorkspaceID = store.workspaces.contains { $0.id == store.focusedWorkspaceID }
                ? store.focusedWorkspaceID : store.workspaces.first?.id
        }
    }

    /// The card keys and the menu bar's pane items go to: the selected tab's zoomed card, else its terminal with
    /// the keyboard, else its keyboard card. None on a new tab's stand-in.
    var keyboardPane: HostStore.Pane? {
        if let zoomed = zoomedPaneID.flatMap(store.pane), zoomed.tabID == selectedTab?.id {
            return zoomed
        }
        // A split's pane before its terminal takes the keyboard.
        if let pane = newest.flatMap({ store.pane($0.id) }), pane.tabID == selectedTab?.id {
            return pane
        }
        // Not another tab's: its view keeps the keyboard until the shown tab's terminal takes it (after ⌘T, until
        // herdr's tab comes), and ⌘W closed that tab's pane.
        if let id = terminals.keyboardTerminalID, let pane = store.panes.first(where: { $0.terminalID == id }),
           pane.tabID == selectedTab?.id
        {
            return pane
        }
        // A text field has the keyboard: the card that had it last.
        return keyboardCard(selectedTab?.id)
    }

    /// The tab's card that last had the keyboard, else the one before it (it closed), else herdr's focused pane.
    /// Observed, unlike the first responder.
    func keyboardCard(_ tabID: String?) -> HostStore.Pane? {
        let panes = store.panes(in: tabID).filter { !floats($0) }
        let pane = usedTerminals.reversed().lazy.compactMap { id in panes.first { $0.terminalID == id } }.first
        return pane ?? panes.first(where: \.focused)
    }

    /// The selected tab's terminals and the floated ones (terminal id → pane id): the ones that stream.
    var shownTerminals: [String: String] {
        Dictionary(store.panes.compactMap { pane in
            pane.tabID == selectedTab?.id || floats(pane) ? pane.terminalID.map { ($0, pane.id) } : nil
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The pane's terminal, made on first use once the store is connected.
    func terminal(_ pane: HostStore.Pane) -> PaneTerminal? {
        guard let terminalID = pane.terminalID, let client = store.client else { return nil }
        return terminals.terminal(terminalID, pane: pane.id, client: client)
    }

    func tookKeyboard(_ terminalID: String) {
        // The newest's terminal, or one the user chose; not the old one taking it back.
        if terminalID != newest?.from {
            newest = nil
        }
        if let pane = store.panes.first(where: { $0.terminalID == terminalID }), !floats(pane) {
            use(terminalID)
        }
    }

    /// The page is in view and its shown terminals stream: a newly selected tab gives the keyboard back to the
    /// card it had; herdr's focused pane only picks it the first time a tab is shown. Later snapshots leave it
    /// alone, unless the card with the keyboard closed: then the tab's next card takes it.
    func shown(alive: Set<String>) {
        // Only what was alive before: a split's new terminal joins the history before a snapshot has it.
        let gone = self.alive.subtracting(alive)
        self.alive = alive
        let closed = usedTerminals.last.map(gone.contains) ?? false
        // Assigned, not edited in place: Observation skips an equal value; removeAll notified at each snapshot.
        usedTerminals = usedTerminals.filter { !gone.contains($0) }
        if closed || selectedTab?.id != keyboardTabID {
            focusKeyboardCard()
        }
    }

    /// The terminals alive at the last `shown`.
    @ObservationIgnored private var alive: Set<String> = []

    /// The terminal is the latest to have the keyboard, so its tab's keyboard card.
    func use(_ terminalID: String) {
        usedTerminals.removeAll { $0 == terminalID }
        usedTerminals.append(terminalID)
    }

    /// Gives the keyboard to the selected tab's card: the one it last had, else herdr's focused pane.
    func focusKeyboardCard() {
        guard let tab = selectedTab else { return }
        let tabPanes = store.panes(in: tab.id).filter { $0.terminalID != nil && !floats($0) }
        // A moved pane not in the tab yet: wait for the snapshot (`shown` asks again). Giving the keyboard to
        // another card meanwhile would record that card as the tab's keyboard card (`tookKeyboard`) for good.
        if let moved = movedTerminal, usedTerminals.last == moved {
            guard tabPanes.contains(where: { $0.terminalID == moved }) else { return }
            movedTerminal = nil
        }
        let pane = keyboardCard(tab.id) ?? tabPanes.first
        if let pane, let terminalID = pane.terminalID {
            keyboardTabID = tab.id
            // Made now if its card has not drawn yet (a tab just jumped to); it takes the keyboard once it is in
            // the window.
            _ = terminal(pane)
            terminals.focus(terminalID)
        }
    }

    /// Selects the pane's workspace and tab and gives the pane the keyboard (never herdr focus, D13). A zoom of
    /// another card restores, so the pane shows. A floated pane's window comes to the front instead.
    func go(to pane: HostStore.Pane) {
        guard !floats(pane) else { return float(pane) }
        guard let workspace = store.workspace(of: pane.tabID) else { return }
        newest = nil
        select(workspace, tab: pane.tabID)
        if zoomedPaneID != pane.id, store.pane(zoomedPaneID ?? "")?.tabID == pane.tabID {
            zoomedPaneID = nil
        }
        if let terminalID = pane.terminalID {
            use(terminalID)
        }
        focusKeyboardCard()
    }

    /// Selects the tab before or after the selected one, round the ends.
    func step(_ offset: Int) {
        guard let workspace = selectedWorkspace, !workspace.tabs.isEmpty else { return }
        let tabs = workspace.tabs
        selectedTabIDs[workspace.id] = tabs[(selectedIndex(in: workspace) + offset + tabs.count) % tabs.count].id
    }

    /// The sidebar's order: each workspace, its worktrees right after it.
    var sidebarWorkspaces: [HostStore.Workspace] {
        store.groups.flatMap(\.self)
    }

    /// The workspace before or after the selected one in the sidebar, round the ends (⌃⌘[ ⌃⌘]).
    func stepWorkspace(_ offset: Int) {
        let workspaces = sidebarWorkspaces
        guard let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        select(workspaces[(index + offset + workspaces.count) % workspaces.count])
    }

    /// Zooms the card, or restores the layout when it is the zoomed one. The zoomed card gets the keyboard.
    func zoom(_ paneID: String) {
        guard canZoom(paneID) else { return }
        zoomedPaneID = zoomedPaneID == paneID ? nil : paneID
        if findHidden {
            dropFind()
        }
        if zoomedPaneID != nil, let terminalID = store.pane(paneID)?.terminalID {
            terminals.focus(terminalID)
        }
    }

    func canZoom(_ paneID: String) -> Bool {
        zoomedPaneID == paneID || !alone(paneID)
    }

    /// The only card of its tab, or gone.
    private func alone(_ paneID: String) -> Bool {
        let tab = store.pane(paneID)?.tabID
        return store.panes(in: tab).count < 2
    }

    /// The closes being asked about (`close`).
    @ObservationIgnored var asking: Set<String> = []
}

extension Page {
    /// The keyboard goes to the card next to it that way (`SplitNode.neighbor`): the one used last there, else the
    /// one sharing most of its edge. From the tree, at once: herdr's `pane.neighbor` took a round trip and picked
    /// another.
    func moveKeyboard(_ heading: Heading) {
        let used = usedTerminals.compactMap { id in store.panes.first { $0.terminalID == id }?.id }
        guard let from = keyboardPane, let id = selectedTab?.tree?.neighbor(of: from.id, heading, used: used),
              let pane = store.pane(id) else { return }
        go(to: pane)
    }

    /// The pane goes to another tab or workspace; the page follows it there and it keeps the keyboard.
    func move(_ pane: HostStore.Pane, to destination: Destination) async {
        let terminalID = pane.terminalID
        await follow(store.move(pane.id, to: destination), terminalID)
    }

    /// A dragged pane dropped: as a move, the page follows it and it keeps the keyboard. A re-place in its own tab
    /// keeps that tab selected throughout (its pass through a new tab never shows).
    func drop(_ paneID: String, on target: DropTarget) async {
        guard let pane = store.pane(paneID) else { return }
        let terminalID = pane.terminalID
        switch target {
        case let .card(targetID, nil):
            await store.swap(paneID, with: targetID)
            go(to: pane)
        case let .card(targetID, edge?):
            guard let tabID = store.pane(targetID)?.tabID else { return }
            await follow(store.place(paneID, in: tabID, beside: targetID, edge), terminalID)
        case let .tab(tabID):
            await follow(store.place(paneID, in: tabID), terminalID)
        case let .move(destination):
            await move(pane, to: destination)
        }
    }

    /// The page goes to the moved pane's tab once a snapshot shows it (when `select`), and the pane has the
    /// keyboard there. A floated pane stays in its window.
    func follow(_ moved: HerdrKit.Pane?, _ terminalID: String?, select: Bool = true) {
        guard let moved, floating[terminalID ?? ""] == nil else { return }
        if let terminalID {
            use(terminalID)
        }
        movedTerminal = terminalID
        arriving = select ? moved.tabID : arriving
        settle() // In case the snapshot after the move came in already.
        // The next snapshot gives it the keyboard if the store does not show it in its tab yet (`shown`), also when
        // the tab stays selected (a spring-loaded tab, a re-place).
        keyboardTabID = nil
        if moved.tabID == selectedTab?.id {
            focusKeyboardCard()
        }
    }

    /// A new tab in the workspace (the selected one by default), in its keyboard card's directory, else home.
    /// Selected at once as a stand-in ("New Tab", an empty card); herdr's tab takes its place when a snapshot
    /// has it.
    func newTab(in workspace: HostStore.Workspace? = nil) async {
        guard let workspace = workspace ?? selectedWorkspace else { return }
        // Another workspace's, or a stand-in shows (⌘T again): the keyboard card of the tab used last there.
        let tabs = [selectedTabIDs[workspace.id]] + (usedTabIDs[workspace.id] ?? []).reversed()
        let pane = (workspace.id == selectedWorkspaceID ? keyboardPane : nil)
            ?? tabs.lazy.compactMap { self.keyboardCard($0) }.first
        let standIn = store.standIn(in: workspace.id)
        select(workspace, tab: standIn)
        guard let made = await store.newTab(in: workspace.id, cwd: pane?.cwd, of: pane?.id) else {
            store.dropStandIn(standIn)
            return
        }
        store.madeTab(standIn, made)
    }

    /// The snapshot after it selects the new workspace.
    func newWorkspace(label: String? = nil, cwd: String = "~") async {
        arriving = await store.newWorkspace(label: label, cwd: cwd)?.id ?? arriving
    }

    /// The keyboard goes to the previous or next card in the tab's tree, round the ends; not to a floated one.
    func stepCard(_ offset: Int) {
        guard let ids = selectedTab?.tree?.paneIDs.filter({ store.pane($0).map { !floats($0) } == true }),
              let from = keyboardPane,
              let index = ids.firstIndex(of: from.id),
              let pane = store.pane(ids[(index + offset + ids.count) % ids.count]) else { return }
        go(to: pane)
    }
}
