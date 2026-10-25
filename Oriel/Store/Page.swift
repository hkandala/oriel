#if os(macOS)
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
        var selectedWorkspaceID: String?
        /// Each workspace's selected tab. Starts at herdr's active tab.
        var selectedTabIDs: [String: String] = [:] {
            didSet {
                for (workspace, tab) in oldValue where selectedTabIDs[workspace] != tab {
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
        var floating: [String: Bool] = [:]
        /// The card whose header shows the rename field.
        var renamingPaneID: String?
        /// The open find bar (⌘F), on one card.
        var find: Find?
        /// Counts ⌘F presses: each one focuses the open bar's field.
        var findFocus = 0
        /// The strip's scroll offset in pages (1.5 = halfway from the second tab to the third), for the tab marker.
        var stripPage = 0.0
        /// The terminal that last had the keyboard in each tab. Observed: the tab's icon stack puts it in front.
        private var keyboardTerminals: [String: String] = [:]
        /// The tab whose terminal last got the keyboard from the app.
        @ObservationIgnored private var keyboardTabID: String?
        /// A moved pane's terminal, which takes the keyboard once a snapshot shows it in its tab: a write does not wait
        /// for its snapshot.
        @ObservationIgnored private var movedTerminal: String?
        /// A tab this page just made, selected once a snapshot shows it.
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
        /// else the new first (phase 24); a workspace's first selection, or a saved one that is gone, is herdr's
        /// active tab. A gone workspace falls back to herdr's focused one, and a tab this page made is selected once
        /// it shows.
        func settle() {
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
            // Gone, or alone in its tab (moved, or its neighbor closed).
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

        /// The tab's panes for its icon stack, at most 5: the keyboard card's first (herdr's focused pane until one
        /// had the keyboard), then herdr's order.
        func stack(_ tab: HostStore.Tab) -> [HostStore.Pane] {
            let tabPanes = store.panes.filter { $0.tabID == tab.id }
            let front = keyboardCard(tab.id)
            return Array(([front].compactMap(\.self) + tabPanes.filter { $0 !== front }).prefix(5))
        }

        /// The card keys and the menu bar's pane items go to: the selected tab's zoomed card, else the terminal with
        /// the keyboard, else herdr's focused pane of the selected tab.
        var keyboardPane: HostStore.Pane? {
            if let zoomed = zoomedPaneID.flatMap(store.pane), zoomed.tabID == selectedTab?.id {
                return zoomed
            }
            if let id = terminals.keyboardTerminalID, let pane = store.panes.first(where: { $0.terminalID == id }) {
                return pane
            }
            // A text field has the keyboard: the card that had it last.
            return keyboardCard(selectedTab?.id)
        }

        /// The tab's card that last had the keyboard, else herdr's focused pane. Observed, unlike the first responder.
        func keyboardCard(_ tabID: String?) -> HostStore.Pane? {
            let terminalID = tabID.flatMap { keyboardTerminals[$0] }, panes = store.panes.filter { $0.tabID == tabID }
            return panes.first { !floats($0) && $0.terminalID != nil && $0.terminalID == terminalID }
                ?? panes.first { !floats($0) && $0.focused }
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
            if let pane = store.panes.first(where: { $0.terminalID == terminalID }), !floats(pane) {
                keyboardTerminals[pane.tabID] = terminalID
            }
        }

        /// The page is in view and its shown terminals stream: a newly selected tab gives the keyboard back to the
        /// card it had; herdr's focused pane only picks it the first time a tab is shown. Later snapshots leave it
        /// alone, unless the card with the keyboard closed: then the tab's next card takes it.
        func shown(alive: Set<String>) {
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
            let tabPanes = store.panes.filter { $0.tabID == tab.id && $0.terminalID != nil && !floats($0) }
            // A moved pane not in the tab yet: wait for the snapshot (`shown` asks again). Giving the keyboard to
            // another card meanwhile would record that card as the tab's keyboard card (`tookKeyboard`) for good.
            if let moved = movedTerminal, keyboardTerminals[tab.id] == moved {
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
            select(workspace, tab: pane.tabID)
            if zoomedPaneID != pane.id, store.pane(zoomedPaneID ?? "")?.tabID == pane.tabID {
                zoomedPaneID = nil
            }
            if let terminalID = pane.terminalID {
                keyboardTerminals[pane.tabID] = terminalID
            }
            focusKeyboardCard()
        }

        /// Selects the tab before or after the selected one, round the ends.
        func step(_ offset: Int) {
            guard let workspace = selectedWorkspace, !workspace.tabs.isEmpty else { return }
            let tabs = workspace.tabs
            let index = tabs.firstIndex { $0.id == selectedTabIDs[workspace.id] } ?? 0
            selectedTabIDs[workspace.id] = tabs[(index + offset + tabs.count) % tabs.count].id
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

        /// The tab's title, from herdr's label; herdr's default label (a bare number) gives the front card's program
        /// and folder instead (D65), "New Tab" until the program is known (a new pane's is asked a second late).
        func title(_ tab: HostStore.Tab) -> (name: String, folder: String?) {
            guard !tab.label.isEmpty, tab.label.allSatisfy(\.isNumber) else { return (tab.label, nil) }
            guard let pane = stack(tab).first, let name = pane.programName else { return ("New Tab", nil) }
            // The folder's name ("pi oriel"), as in Rex: a tab is narrow.
            return (name, pane.folder.map { $0 == "~" ? $0 : ($0 as NSString).lastPathComponent })
        }

        /// The title in one string, for the window title and menus.
        func titleText(_ tab: HostStore.Tab) -> String {
            let title = title(tab)
            return [title.name, title.folder ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        }

        /// "‹workspace› · ‹tab›", for agent rows and notifications.
        func place(_ pane: HostStore.Pane) -> String {
            let workspace = store.workspace(of: pane.tabID)
            let tab = workspace?.tabs.first { $0.id == pane.tabID }
            return [workspace?.label, tab.map(titleText)].compactMap(\.self).joined(separator: " · ")
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
            return store.panes.count { $0.tabID == tab } < 2
        }

        /// Closes it, or asks first in this window (D41).
        func close(_ close: HostStore.Close) {
            Task { closing = await store.ask(close) }
        }

        /// A split restores a zoomed layout first, as tmux does: the new pane shows.
        func split(_ paneID: String, _ direction: SplitNode.Direction, before: Bool = false) async {
            zoomedPaneID = nil
            await store.split(paneID, direction, before: before)
        }

        /// The keyboard goes to the nearest card that way, as herdr's `pane.neighbor` finds it (read only).
        func moveKeyboard(_ heading: Heading) async {
            guard let from = keyboardPane, let client = store.client,
                  let id = try? await client.neighbor(of: from.id, heading), let pane = store.pane(id) else { return }
            go(to: pane)
        }

        /// The keyboard goes to the previous or next card in the tab's tree, round the ends.
        func stepCard(_ offset: Int) {
            guard let ids = selectedTab?.tree?.paneIDs, let from = keyboardPane,
                  let index = ids.firstIndex(of: from.id),
                  let pane = store.pane(ids[(index + offset + ids.count) % ids.count]) else { return }
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

        /// The page goes to the moved pane's tab once a snapshot shows it, and the pane has the keyboard there.
        private func follow(_ moved: HerdrKit.Pane?, _ terminalID: String?) {
            guard let moved else { return }
            keyboardTerminals[moved.tabID] = terminalID
            movedTerminal = terminalID
            arriving = moved.tabID
            // In case the snapshot after the move came in already.
            settle()
            // The next snapshot gives it the keyboard if the store does not show it in its tab yet (`shown`), also when
            // the tab stays selected (a spring-loaded tab, a re-place).
            keyboardTabID = nil
            if moved.tabID == selectedTab?.id {
                focusKeyboardCard()
            }
        }

        /// A new tab in the workspace (the selected one by default), in its keyboard card's directory, else home;
        /// the snapshot after it selects it.
        func newTab(in workspace: HostStore.Workspace? = nil) async {
            guard let workspace = workspace ?? selectedWorkspace else { return }
            // Another workspace's: the keyboard card of its selected tab.
            let pane = workspace.id == selectedWorkspaceID ? keyboardPane : keyboardCard(selectedTabIDs[workspace.id])
            arriving = await store.newTab(in: workspace.id, cwd: pane?.cwd, of: pane?.id) ?? arriving
        }

        /// The snapshot after it selects the new workspace.
        func newWorkspace(label: String? = nil, cwd: String = NSHomeDirectory()) async {
            arriving = await store.newWorkspace(label: label, cwd: cwd)?.id ?? arriving
        }
    }

    extension Page {
        /// Go to Directory (`directory`, a `cd`) or Insert Path: the system panel at the keyboard card's folder, fresh
        /// from herdr, then the chosen path typed into the card, quoted. Go to Directory asks again that the card runs
        /// only its shell (D41). ponytail: This Mac only; remote machines need another picker.
        func choosePath(directory: Bool) async {
            guard let pane = keyboardPane, let client = store.client, let window = NSApp.keyWindow else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = !directory
            panel.directoryURL = await (try? client.pane(pane.id).cwd).map { URL(filePath: $0) }
            guard await panel.beginSheetModal(for: window) == .OK, let path = panel.url?.path(percentEncoded: false)
            else { return }
            let quoted = "'" + path.replacing("'", with: #"'\''"#) + "'"
            if directory {
                do {
                    guard try await client.program(pane.id)?.isShell == true else {
                        await store.show(Notice(text: "A program is running in the pane", tone: .warning))
                        return
                    }
                } catch {
                    await store.show(Notice(text: error.localizedDescription))
                    return
                }
            }
            await store.write { client in
                try await client.sendInput(directory ? "cd -- \(quoted)" : quoted, keys: directory ? ["enter"] : [],
                                           pane: pane.id)
            }
        }
    }
#endif
