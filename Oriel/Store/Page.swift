#if os(macOS)
    import Foundation
    import HerdrKit
    import Observation

    /// One session's page in a window: its store, and the window's own selection in it (design D43). Switching
    /// pages brings the selection back.
    @MainActor @Observable
    final class Page: Identifiable {
        let store: HostStore
        /// The window's terminals.
        let terminals: PaneViewRegistry
        /// The app's own selection, never herdr's focus (D13).
        var selectedWorkspaceID: String?
        /// Each workspace's selected tab. Starts at herdr's active tab.
        var selectedTabIDs: [String: String] = [:]
        /// The app's own zoom (design D11): this card fills its tab's page.
        var zoomedPaneID: String?
        /// The strip's scroll offset in pages (1.5 = halfway from the second tab to the third), for the tab marker.
        var stripPage = 0.0
        /// The terminal that last had the keyboard in each tab. Observed: the tab's icon stack puts it in front.
        private var keyboardTerminals: [String: String] = [:]
        /// The tab whose terminal last got the keyboard from the app.
        @ObservationIgnored private var keyboardTabID: String?
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

        /// After each snapshot: a selection that is gone falls back to herdr's active tab or focused workspace, and
        /// a tab this page made is selected once it shows.
        func settle() {
            for workspace in store.workspaces where !workspace.tabs.contains(where: {
                $0.id == selectedTabIDs[workspace.id]
            }) {
                selectedTabIDs[workspace.id] = workspace.tabs.contains { $0.id == workspace.activeTabID }
                    ? workspace.activeTabID : workspace.tabs.first?.id
            }
            if let id = zoomedPaneID, store.pane(id) == nil {
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
            let keyboard = keyboardTerminals[tab.id]
            let front = tabPanes.first { $0.terminalID != nil && $0.terminalID == keyboard }
                ?? tabPanes.first(where: \.focused)
            return Array(([front].compactMap(\.self) + tabPanes.filter { $0 !== front }).prefix(5))
        }

        /// The card keys go to: the terminal with the keyboard, else herdr's focused pane of the selected tab.
        var keyboardPane: HostStore.Pane? {
            if let id = terminals.keyboardTerminalID, let pane = store.panes.first(where: { $0.terminalID == id }) {
                return pane
            }
            return store.panes.first { $0.tabID == selectedTab?.id && $0.focused }
        }

        /// The selected tab's terminals (terminal id → pane id): the ones that stream.
        var shownTerminals: [String: String] {
            Dictionary(store.panes.compactMap { pane in
                pane.tabID == selectedTab?.id ? pane.terminalID.map { ($0, pane.id) } : nil
            }, uniquingKeysWith: { first, _ in first })
        }

        /// The pane's terminal, made on first use once the store is connected.
        func terminal(_ pane: HostStore.Pane) -> PaneTerminal? {
            guard let terminalID = pane.terminalID, let client = store.client else { return nil }
            return terminals.terminal(terminalID, pane: pane.id, client: client)
        }

        /// A terminal of this page took the keyboard.
        func tookKeyboard(_ terminalID: String) {
            if let tabID = store.panes.first(where: { $0.terminalID == terminalID })?.tabID {
                keyboardTerminals[tabID] = terminalID
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
            let tabPanes = store.panes.filter { $0.tabID == tab.id && $0.terminalID != nil }
            let pane = tabPanes.first { $0.terminalID == keyboardTerminals[tab.id] }
                ?? tabPanes.first(where: \.focused) ?? tabPanes.first
            if let pane, let terminalID = pane.terminalID {
                keyboardTabID = tab.id
                // Made now if its card has not drawn yet (a tab just jumped to); it takes the keyboard once it is in
                // the window.
                _ = terminal(pane)
                terminals.focus(terminalID)
            }
        }

        /// Selects the pane's workspace and tab and gives the pane the keyboard (never herdr focus, D13).
        func go(to pane: HostStore.Pane) {
            guard let workspace = store.workspace(of: pane.tabID) else { return }
            select(workspace, tab: pane.tabID)
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

        /// The tab's title, from herdr's label; herdr's default label (a bare number) gives the front card's program
        /// and folder instead (D65).
        func title(_ tab: HostStore.Tab) -> (name: String, folder: String?) {
            guard !tab.label.isEmpty, tab.label.allSatisfy(\.isNumber), let pane = stack(tab).first,
                  let name = pane.programName else { return (tab.label, nil) }
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
            zoomedPaneID = zoomedPaneID == paneID ? nil : paneID
            if zoomedPaneID != nil, let terminalID = store.pane(paneID)?.terminalID {
                terminals.focus(terminalID)
            }
        }

        /// A split restores a zoomed layout first, as tmux does: the new pane shows.
        func split(_ paneID: String, _ direction: SplitNode.Direction) async {
            zoomedPaneID = nil
            await store.split(paneID, direction)
        }

        /// A new tab in the workspace (the selected one by default), in its keyboard card's directory, else home;
        /// the snapshot after it selects it.
        func newTab(in workspace: HostStore.Workspace? = nil) async {
            guard let workspace = workspace ?? selectedWorkspace else { return }
            // Another workspace's: the keyboard card of its selected tab.
            let tab = selectedTabIDs[workspace.id]
            let pane = workspace.id == selectedWorkspaceID ? keyboardPane
                : store.panes.first { $0.tabID == tab && $0.terminalID == tab.flatMap { keyboardTerminals[$0] } }
                ?? store.panes.first { $0.tabID == tab && $0.focused }
            arriving = await store.newTab(in: workspace.id, cwd: pane?.cwd, of: pane?.id) ?? arriving
        }

        /// The snapshot after it selects the new workspace.
        func newWorkspace(label: String? = nil) async {
            arriving = await store.newWorkspace(label: label)?.id ?? arriving
        }
    }
#endif
