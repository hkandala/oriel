#if os(macOS)
    import AppKit
    import HerdrKit

    /// The pages of one window, in order, and the one in view (design D43). Each page's store is the app's one
    /// store of that session, shared with the other windows that show it; one `PaneViewRegistry` holds every page's
    /// terminals.
    @MainActor @Observable
    final class WindowPages {
        private(set) var list: [Page] = []
        /// The page in view; nil only until the first page opens.
        private(set) var current: Page?
        let terminals = PaneViewRegistry()
        /// The window is key (D14).
        @ObservationIgnored private var key = false
        /// A notification or Dock row clicked before its page or pane was there.
        @ObservationIgnored private var pending: String?
        /// Its AppKit window, to bring it to the front.
        @ObservationIgnored weak var window: NSWindow?

        /// The open windows, the one that was key last first; added once a window restored its pages (a `@State`
        /// initial value is made again with each view, so not in `init`).
        static var windows: [WindowPages] = []
        /// A click that came before any window (one that started the app).
        private static var early: String?

        init() {
            terminals.onKeyboard = { [weak self] terminalID in self?.current?.tookKeyboard(terminalID) }
            // Return may have started or ended a program.
            terminals.onReturn = { [weak self] terminalID in
                guard let store = self?.current?.store,
                      let pane = store.panes.first(where: { $0.terminalID == terminalID }) else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    await store.askProgram(pane.id)
                }
            }
            // Input in a card of a watched session makes this window its controller (D66).
            terminals.onInput = { [weak self] in
                if let self, let store = current?.store, store.windows.first !== self {
                    control(store)
                }
            }
            terminals.watches = { [weak self] terminalID in
                self?.list.first { $0.store.panes.contains { $0.terminalID == terminalID } }?.watched ?? false
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

        /// Shows the session's page; one not open yet opens after the page in view, its store connecting (`start`:
        /// its server is started first). A session another window shows is watched until this window takes it.
        @discardableResult
        func open(_ session: String, start: Bool = false) -> Page {
            if let page = list.first(where: { $0.id == session }) {
                show(page)
                return page
            }
            let store = HostStore.named(session, start: start)
            store.windows.append(self)
            let page = Page(store: store, terminals: terminals)
            page.settle()
            list.insert(
                page,
                at: current.flatMap { current in list.firstIndex { $0 === current } }.map { $0 + 1 } ?? list.endIndex,
            )
            show(page)
            return page
        }

        func show(_ page: Page) {
            current = page
            showTerminals()
        }

        func page(_ store: HostStore) -> Page? {
            list.first { $0.store === store }
        }

        /// After each snapshot of a store this window shows.
        func snapshotted(_ store: HostStore) {
            page(store)?.settle()
            showTerminals()
            showPending()
        }

        /// Removes the page from the window; its terminals close. Never the last page.
        func close(_ page: Page) {
            guard list.count > 1, let index = list.firstIndex(where: { $0 === page }) else { return }
            list.remove(at: index)
            if current === page {
                show(list[max(index - 1, 0)])
            }
            showTerminals()
            leave(page.store)
        }

        /// The window closed: every page leaves and every terminal closes.
        func closed() {
            Self.windows.removeAll { $0 === self }
            terminals.show([:], alive: [], client: nil)
            list.forEach { leave($0.store) }
            list = []
        }

        /// This window no longer shows the store: the next window controls it, or, the last one gone, it disconnects.
        private func leave(_ store: HostStore) {
            let controlled = store.windows.first === self
            store.windows.removeAll { $0 === self }
            if let next = store.windows.first {
                if controlled {
                    next.control(store)
                }
            } else {
                Notifications.remove(store.panes, session: store.session)
                store.disconnect()
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
        /// pages.
        func showTerminals() {
            guard let current else { return }
            let alive = Set(list.flatMap { $0.store.panes.compactMap(\.terminalID) })
            terminals.show(current.shownTerminals, alive: alive, client: current.store.client)
            current.shown(alive: alive)
        }
    }

    extension HostStore {
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
