import AppKit
import HerdrKit
import SwiftUI

/// The pages of one window, in order, and the one in view (design D43). Each page's store is the app's one
/// store of that session, shared with the other windows that show it; one `PaneViewRegistry` holds every page's
/// terminals.
@MainActor @Observable
final class WindowPages {
    /// The machine whose sessions the pages are (D43): one per window.
    var machine = Machine.thisMac
    private(set) var list: [Page] = []
    /// Sessions with no page here, for panes `oriel://float` floated: no row, no strip page, no selection (so a
    /// float never gives their cards the keyboard). Each goes with its last float. ponytail: not saved.
    var floatOnly: [Page] = []
    /// An `oriel://float` URL's session and pane, until its store answers.
    @ObservationIgnored var floatPending: (page: Page, pane: String)?
    /// What ssh asks while this window connects a remote machine; its dialog answers it.
    var question: Question?
    /// The remote host dialog's machine: a new one to add, or one of the list to edit.
    var hostDialog: Machine?
    /// The page in view; nil until the first page opens, and after the window closed.
    private(set) var current: Page?
    let terminals = PaneViewRegistry()
    /// The window is visible (its scene is active): its page in view shows git status.
    var visible = false
    /// The overview is open (D70): its tiles laid out (`overviewTabs`, by page, the latest last), up to a cap,
    /// stream and draw (`overviewLive`); `leaving` while its tile zooms to the page; `tileScale`, the tiles' scale
    /// of the strip's page (a third before they laid out), for snapshots; `afterOverview` runs after the zoom;
    /// `overviewScrolling` while its grid scrolls, `overviewSliding` while a swipe moves its pages
    /// (`settleOverview`).
    var overview = false
    var leaving = false
    @ObservationIgnored var overviewTabs: [String: [String]] = [:]
    @ObservationIgnored var overviewSettling: Task<Void, Never>?
    private(set) var overviewLive: Set<String> = []
    @ObservationIgnored var tileScale: CGFloat = 0.35
    @ObservationIgnored var overviewScrolling = false
    @ObservationIgnored var overviewSliding = false
    @ObservationIgnored var afterOverview: (() -> Void)?
    /// A floating panel (the palette, the shortcuts) is open: its Esc is its own.
    @ObservationIgnored var panelOpen = false
    /// The window is key (D14).
    @ObservationIgnored private var key = false
    /// A notification or Dock row clicked before its page or pane was there.
    @ObservationIgnored private var pending: String?
    /// Its AppKit window, to bring it to the front.
    @ObservationIgnored weak var window: NSWindow?

    /// The open windows, the last key one first; added once its pages are restored (a `@State` is made per view).
    static var windows: [WindowPages] = []
    /// The window closed.
    @ObservationIgnored private var gone = false
    /// A click or URL that came before any window (one that started the app).
    static var early: (() -> Void)?
    /// Folders dropped on the Dock icon, waiting for a live page (a drop can start the app).
    private static var folders: [URL] = []
    /// SwiftUI's window opener, from the menu bar's commands (they exist with no window).
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
            await store.askProgram(pane.id, soon: true)
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
        if let early = Self.early {
            Self.early = nil
            early()
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
        // A float-only page becomes a page, its floats kept.
        let page = floatOnly.firstIndex { $0.id == session }.map { floatOnly.remove(at: $0) } ?? {
            let store = HostStore.named(session, on: machine, start: start)
            store.windows.append(self)
            return Page(store: store, terminals: terminals)
        }()
        page.settle()
        list.append(page)
        show(page)
    }

    /// A page shown again gives its keyboard card the keyboard back (`shown`): another page's card took it since.
    func show(_ page: Page) {
        if page !== current {
            page.keyboardTabID = nil
        }
        current = page
        showTerminals()
    }

    /// The page before (-1) or after (1) the one in view.
    func neighbor(_ offset: Int) -> Page? {
        list.firstIndex { $0 === current }.map { $0 + offset }
            .flatMap { list.indices.contains($0) ? list[$0] : nil }
    }

    func step(_ offset: Int) {
        if let page = neighbor(offset) {
            show(page)
        }
    }

    func page(_ store: HostStore) -> Page? {
        list.first { $0.store === store }
    }

    func page(of terminalID: String) -> Page? {
        withFloats.first { $0.store.panes.contains { $0.terminalID == terminalID } }
    }

    /// After each snapshot of a store this window shows.
    func snapshotted(_ store: HostStore) {
        page(store)?.settle()
        // A floated pane herdr closed: its window closes.
        if let page = withFloats.first(where: { $0.store === store }), store.state == .live {
            // herdr's panes, not the shown ones: a close shown at once may still come back (`Ahead`).
            let alive = page.floating.filter { id, _ in store.last?.panes.contains { $0.terminalID == id } ?? true }
            if alive.count < page.floating.count {
                page.floating = alive
            }
        }
        showTerminals(snapshot: true)
        showPending()
        showFloatPending()
        if Self.windows.first === self {
            openFolders()
        }
    }

    /// A workspace in each folder, in the session of the last key window's page in view; the last one selected.
    static func open(folders urls: [URL]) {
        folders += urls
        windows.first?.openFolders()
    }

    private func openFolders() {
        // ponytail: a Mac folder means nothing to a remote machine; they wait for a page of This Mac.
        guard let page = current, page.store.state == .live, !page.store.machine.isRemote, !Self.folders.isEmpty
        else { return }
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
        leaveAll()
        question?.answer(nil)
    }

    /// A new window on the machine (D43); the others stay. `connect`: it connects at once, asking what ssh asks.
    static func open(machine: Machine, connect: Bool = false) {
        opening = openWindow == nil ? nil : (machine, connect)
        openWindow?(id: "main")
    }

    /// `open(machine:)`'s, for the new window. ponytail: one; a queue if two quick opens ever clash.
    static var opening: (machine: Machine, connect: Bool)?

    private func leaveAll() {
        let pages = withFloats
        floatOnly = []
        for item in pages {
            item.dropFind()
            item.floating = [:]
        }
        terminals.show([:], alive: [], client: nil)
        pages.forEach { leave($0.store) }
        list = []
        // Its content goes too: nothing of the window may stream again.
        current = nil
    }

    /// One question of ssh's, as a dialog in this window; nil when the user cancels or a newer one comes.
    func ask(_ text: String) async -> String? {
        question?.answer(nil)
        let id = UUID()
        return await withCheckedContinuation { continuation in
            // Once: a second click, or a late answer to a question a newer one replaced, does nothing.
            question = Question(id: id, text: text) { [weak self] answer in
                guard self?.question?.id == id else { return }
                self?.question = nil
                continuation.resume(returning: answer)
            }
        }
    }

    struct Question: Identifiable {
        let id: UUID
        let text: String
        /// Called once.
        let answer: (String?) -> Void
    }

    /// This window no longer shows the store: the next window controls it, or, the last one gone, it disconnects.
    func leave(_ store: HostStore) {
        let controlled = store.windows.first === self
        store.windows.removeAll { $0 === self }
        store.markShown()
        // A key window that goes no longer looks at its tabs (D14), unless another key window that shows the store
        // set them first (as in `look`).
        if key, !store.windows.contains(where: \.key) {
            store.lookingTabID = nil
        }
        if store.windows.isEmpty {
            Notifications.remove(store.panes, of: store)
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
                Notifications.remove(page.store.panes(in: tabID), of: page.store)
            }
        }
    }

    /// Selects an agent's pane from outside the windows (a notification, the Dock menu) by its notification id,
    /// "‹machine id›|‹session›|‹terminal id›": the terminal outlives a pane id that changed. It shows in the window
    /// of the machine that was key last among those with the page open, else the page opens in the machine's
    /// front window; the pane is selected once a snapshot shows it. With no window of the machine, nothing opens.
    /// ponytail: switch the front window to the machine when such a click is missed.
    static func go(to id: String) {
        let parts = id.split(separator: "|", maxSplits: 2).map(String.init)
        let machines = windows.filter { $0.machine.id == parts.first }
        guard let window = machines.first(where: { $0.list.contains { $0.id == parts.dropFirst().first } })
            ?? machines.first
        else {
            if windows.isEmpty {
                early = { go(to: id) }
            }
            return
        }
        window.window?.makeKeyAndOrderFront(nil)
        window.pending = id
        window.showPending()
    }

    /// Streams the shown tab of the page in view (see the registry) and the overview's live tiles (no visits);
    /// drops closed panes' and pages' terminals. A snapshot hands the keyboard to a card only
    /// while no text field has it: typing in the palette or a rename field must not go on because a pane closed.
    func showTerminals(snapshot: Bool = false) {
        guard let current else { return }
        // A find bar whose card is out of view closes: herdr's viewport is shared, it must not stay scrolled. A
        // floated pane's stays in view.
        for page in withFloats where page.findHidden || page !== current
            && page.store.pane(page.find?.paneID ?? "").map(page.floats) != true
        {
            page.dropFind()
        }
        let alive = Set(withFloats.flatMap { $0.store.panes.compactMap(\.terminalID) })
        // The other pages' floated panes stream too (D50), made with their own page's client.
        var shown = current.shownTerminals
        for page in withFloats where page !== current {
            for pane in page.store.panes where page.floats(pane) {
                if let id = pane.terminalID, page.terminal(pane) != nil {
                    shown[id] = pane.id
                }
            }
        }
        let unvisited = overview ? overviewStreams(current, snapshot: snapshot) : [:]
        overviewLive = overview ? Set(unvisited.keys).union(current.shownTerminals.keys) : []
        // herdr's, for the terminals: a close shown at once may come back (`Ahead`) with its picture.
        let kept = alive.union(withFloats.flatMap { ($0.store.last?.panes ?? []).compactMap(\.terminalID) })
        terminals.show(shown, unvisited: unvisited, alive: kept, client: current.store.client)
        // Not while the overview or a panel (the palette, Open Session: ⌥⌘[ ] work under it) has the keyboard.
        if !overview, !panelOpen, !snapshot || !(window?.firstResponder is NSText) {
            current.shown(alive: alive)
        }
        markShown()
    }
}

extension WindowPages {
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
        // A notification's or the Dock's pane shows at once, out of the overview.
        if overview {
            closeOverview()
        }
        show(page)
        page.go(to: pane)
    }
}

extension HostStore {
    /// Each window settles its page's selection on the snapshot; its notifications go once per session.
    func snapshotted(_ changes: [Seen.Change]) {
        for window in windows {
            // Before its float windows close: a replaced floated pane's new pane floats.
            window.withFloats.first { $0.store === self }?.floatReplaced()
            window.snapshotted(self)
        }
        if let page = windows.lazy.compactMap({ $0.page(self) }).first {
            Notifications.post(changes, page)
        }
    }
}
