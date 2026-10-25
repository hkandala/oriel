#if os(macOS)
    import AppKit
    import HerdrKit
    import SwiftUI

    /// The pages of one window, in order, and the one in view (design D43). Each page's store is the app's one
    /// store of that session, shared with the other windows that show it; one `PaneViewRegistry` holds every page's
    /// terminals.
    @MainActor @Observable
    final class WindowPages {
        private(set) var list: [Page] = []
        /// The page in view; nil until the first page opens, and after the window closed.
        private(set) var current: Page?
        let terminals = PaneViewRegistry()
        /// The window is visible (its scene is active): its page in view shows git status.
        var visible = false
        /// The window is key (D14).
        @ObservationIgnored private var key = false
        /// A notification or Dock row clicked before its page or pane was there.
        @ObservationIgnored private var pending: String?
        /// Its AppKit window, to bring it to the front.
        @ObservationIgnored weak var window: NSWindow?

        /// The open windows, the one that was key last first; added once a window restored its pages (a `@State`
        /// initial value is made again with each view, so not in `init`).
        static var windows: [WindowPages] = []
        /// The window closed.
        @ObservationIgnored private var gone = false
        /// A click that came before any window (one that started the app).
        private static var early: String?
        /// Folders dropped on the Dock icon, waiting for a live page (a drop can start the app).
        private static var folders: [URL] = []
        /// SwiftUI's window opener, from the menu bar's commands, for the app delegate.
        static var openWindow: OpenWindowAction?

        init() {
            terminals.pages = self
        }

        /// Return in a terminal may have started or ended a program.
        func returned(_ terminalID: String) {
            guard let page = current, let pane = page.store.panes.first(where: { $0.terminalID == terminalID })
            else { return }
            let store = page.store
            // The find bar reads the pane again at its next step.
            if page.find?.paneID == pane.id {
                page.find?.stale = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1))
                await store.askProgram(pane.id)
            }
        }

        /// Input in a card of a watched session makes this window its controller (D66).
        func input(_ terminalID: String) {
            if let store = page(of: terminalID)?.store, store.windows.first !== self {
                control(store)
            }
        }

        /// The window restored its pages: it joins the open windows, and takes a click that came before it.
        func opened() {
            // Already there when it became key first.
            if !Self.windows.contains(where: { $0 === self }) {
                Self.windows.append(self)
            }
            if let id = Self.early {
                Self.early = nil
                Self.go(to: id)
            }
        }

        /// Shows the session's page; one not open yet opens last, its store connecting (`start`:
        /// its server is started first). A session another window shows is watched until this window takes it.
        func open(_ session: String, start: Bool = false) {
            // A late open (a start that finished, a restore) after the window closed.
            guard !gone else { return }
            if let page = list.first(where: { $0.id == session }) {
                show(page)
                return
            }
            let store = HostStore.named(session, start: start)
            store.windows.append(self)
            let page = Page(store: store, terminals: terminals)
            page.settle()
            list.append(page)
            show(page)
        }

        func show(_ page: Page) {
            current = page
            showTerminals()
        }

        /// The page before (-1) or after (1) the one in view.
        func neighbor(_ offset: Int) -> Page? {
            list.firstIndex { $0 === current }.map { $0 + offset }
                .flatMap { list.indices.contains($0) ? list[$0] : nil }
        }

        func page(_ store: HostStore) -> Page? {
            list.first { $0.store === store }
        }

        func page(of terminalID: String) -> Page? {
            list.first { $0.store.panes.contains { $0.terminalID == terminalID } }
        }

        /// The terminal shows in a floating window (D50).
        func floats(_ terminalID: String) -> Bool {
            list.contains { $0.floating[terminalID] != nil }
        }

        /// After each snapshot of a store this window shows.
        func snapshotted(_ store: HostStore) {
            page(store)?.settle()
            // A floated pane herdr closed: its window closes.
            if let page = page(store), store.state == .live {
                let alive = page.floating.filter { id, _ in store.panes.contains { $0.terminalID == id } }
                if alive.count < page.floating.count {
                    page.floating = alive
                }
            }
            showTerminals(snapshot: true)
            showPending()
            if Self.windows.first === self {
                openFolders()
            }
        }

        /// A workspace in each folder, in the session of the last key window's page in view; the last one is selected
        /// when it appears.
        static func open(folders urls: [URL]) {
            folders += urls
            windows.first?.openFolders()
        }

        private func openFolders() {
            guard let page = current, page.store.state == .live, !Self.folders.isEmpty else { return }
            let urls = Self.folders
            Self.folders = []
            Task {
                for url in urls {
                    await page.newWorkspace(cwd: url.path(percentEncoded: false))
                }
            }
        }

        /// Removes the page from the window; its terminals close. Never the last page.
        func close(_ page: Page) {
            guard list.count > 1, let index = list.firstIndex(where: { $0 === page }) else { return }
            page.dropFind()
            page.floating = [:]
            list.remove(at: index)
            if current === page {
                show(list[max(index - 1, 0)])
            }
            showTerminals()
            leave(page.store)
        }

        /// The window closed: every page leaves and every terminal closes.
        func closed() {
            gone = true
            Self.windows.removeAll { $0 === self }
            for item in list {
                item.dropFind()
                item.floating = [:]
            }
            terminals.show([:], alive: [], client: nil)
            list.forEach { leave($0.store) }
            list = []
            // Its content goes too: nothing of the window may stream again.
            current = nil
        }

        /// This window no longer shows the store: the next window controls it, or, the last one gone, it disconnects.
        private func leave(_ store: HostStore) {
            let controlled = store.windows.first === self
            store.windows.removeAll { $0 === self }
            // A key window that goes no longer looks at its tabs (D14).
            if key {
                store.lookingTabID = nil
            }
            if store.windows.isEmpty {
                Notifications.remove(store.panes, session: store.session)
                store.disconnect()
                HostStore.showBadge()
            } else if controlled {
                store.windows[0].control(store)
            }
        }

        /// This window controls the session (D66): its streams of it take over, the other windows' watch.
        func control(_ store: HostStore) {
            store.windows.removeAll { $0 === self }
            store.windows.insert(self, at: 0)
            let ids = Set(store.panes.compactMap(\.terminalID))
            for window in store.windows {
                window.terminals.terminals(ids).forEach { $0.control(window === self) }
            }
        }

        /// The tab the user looks at (D14): the selected tab of the page in view while the window is key; none on the
        /// other pages. Its panes' notifications go. A window that stops being key leaves alone a store another window
        /// shows while key (the two calls come in either order).
        func look(key: Bool) {
            self.key = key
            if key {
                Self.windows.removeAll { $0 === self }
                Self.windows.insert(self, at: 0)
            }
            for page in list where key || !page.store.windows.contains(where: \.key) {
                let tabID = key && page === current ? page.selectedTab?.id : nil
                page.store.lookingTabID = tabID
                if let tabID {
                    Notifications.remove(page.store.panes.filter { $0.tabID == tabID }, session: page.id)
                }
            }
        }

        /// Selects an agent's pane from outside the windows (a notification, the Dock menu) by its notification id,
        /// "local|‹session›|‹terminal id›": the terminal outlives a pane id that changed. It shows in the window that
        /// was key last among those with the page open, else the page opens in the front window; the pane is
        /// selected once a snapshot shows it.
        static func go(to id: String) {
            let session = id.split(separator: "|", maxSplits: 2).dropFirst().first.map(String.init)
            guard let window = windows.first(where: { $0.list.contains { $0.id == session } }) ?? windows.first else {
                early = id
                return
            }
            window.window?.makeKeyAndOrderFront(nil)
            window.pending = id
            window.showPending()
        }

        func showPending() {
            guard let id = pending else { return }
            let parts = id.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3 else {
                pending = nil
                return
            }
            guard let page = list.first(where: { $0.id == parts[1] }) else {
                open(parts[1])
                return
            }
            guard let pane = page.store.panes.first(where: { ($0.terminalID ?? $0.id) == parts[2] }) else {
                // Gone: a dead click does not wait for ever.
                pending = page.store.state == .connecting ? id : nil
                return
            }
            pending = nil
            show(page)
            page.go(to: pane)
        }

        /// Streams the shown tab of the page in view (see the registry), drops the terminals of closed panes and
        /// pages. A snapshot hands the keyboard to a card only while no text field has it: typing in the palette or a
        /// rename field must not go on in a shell because a pane closed elsewhere.
        func showTerminals(snapshot: Bool = false) {
            guard let current else { return }
            // A find bar whose card is out of view closes: herdr's viewport is shared, it must not stay scrolled. A
            // floated pane's stays in view.
            for page in list where page.findHidden || page !== current
                && page.store.pane(page.find?.paneID ?? "").map(page.floats) != true
            {
                page.dropFind()
            }
            let alive = Set(list.flatMap { $0.store.panes.compactMap(\.terminalID) })
            // The other pages' floated panes stream too (D50), made with their own page's client.
            var shown = current.shownTerminals
            for page in list where page !== current {
                for pane in page.store.panes where page.floats(pane) {
                    if let id = pane.terminalID, page.terminal(pane) != nil {
                        shown[id] = pane.id
                    }
                }
            }
            terminals.show(shown, alive: alive, client: current.store.client)
            if !snapshot || !(window?.firstResponder is NSText) {
                current.shown(alive: alive)
            }
        }
    }

    extension HostStore {
        /// Agents that need you over every open session, each once.
        static var needsYou: Int {
            all.reduce(0) { count, store in count + store.panes.count { $0.state == .needsYou } }
        }

        static func showBadge() {
            NSApp.dockTile.badgeLabel = needsYou > 0 ? "\(needsYou)" : nil
        }

        /// Each window settles its page's selection on the snapshot; its notifications go once per session.
        func snapshotted(_ changes: [Seen.Change]) {
            for window in windows {
                window.snapshotted(self)
            }
            if let page = windows.first?.page(self) {
                Notifications.post(changes, page)
            }
        }
    }
#endif
