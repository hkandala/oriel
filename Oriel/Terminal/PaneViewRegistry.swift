import AppKit
import GhosttyTerminal
import HerdrKit

/// Owns every pane's terminal of one window's pages, keyed by `terminal_id`, so SwiftUI never destroys
/// one while the strip scrolls. The shown tab's terminals stream and draw; the `spare` most recently shown others,
/// over all windows, keep their surface without drawing (as Ghostty's hidden tabs) and, on this Mac, their
/// stream, so coming back to them is at once; the rest keep only their last picture (design: what streams). Web
/// cards (browsers and plugins) the same way: the `spareWeb` most recently shown others keep their page; the rest
/// keep their last picture and are made again from their label when shown.
/// ponytail: keyed by terminal id alone; herdr's ids (`term_` and 14 hex digits, from the clock) did not
/// repeat across sessions. Key by session too if they ever do.
@MainActor
final class PaneViewRegistry {
    /// The design's bound on terminals kept out of view, over all windows (D46). Each keeps its surface, about
    /// 6 MB (libghostty frees the swap chain while it does not draw and makes it again in under a millisecond when
    /// shown), a copy of its last picture (17 MB for a full-window card on Retina) and a herdr run of 7 MB. On
    /// Retina: 405 MB with 16 terminals in splits, 653 MB with 33 full-window tabs (190 MB before,
    /// with 4). One evicted comes back under its last picture if the system kept it, else it fades in.
    /// `-spareTerminals N` (defaults `spareTerminals`).
    static let spare = UserDefaults.standard.string(forKey: "spareTerminals").flatMap { Int($0) } ?? 20
    /// The bound on web cards kept out of view, over all windows: each keeps its web view and WebKit's process for
    /// it. Floating windows' cards and cards with unsaved edits are never dropped. `-spareWebCards N` (defaults
    /// `spareWebCards`).
    static let spareWeb = UserDefaults.standard.string(forKey: "spareWebCards").flatMap { Int($0) } ?? 20
    /// Kept web cards of every window, the most recently shown last.
    private static var recentWeb: [Kept] = []
    private struct Kept {
        weak var registry: PaneViewRegistry?
        let id: String
    }

    /// On a memory-pressure warning the kept cards out of view go down to half the bounds.
    private static let pressure = {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { trim(terminals: spare / 2, web: spareWeb / 2) }
        }
        source.resume()
        return source
    }()

    /// Kept terminals of every window (a surface; a stream unless paused), the most recently shown last.
    private(set) static var recent: [PaneTerminal] = []
    /// Its window's pages: they hear of the keyboard, Return and input in its terminals.
    weak var pages: WindowPages?
    private var terminals: [String: PaneTerminal] = [:]
    /// Browser panes' cards (ui/browser), by terminal id as terminals are: a moved card keeps its page.
    private var browsers: [String: Browser] = [:]
    /// The other plugin panes' cards, the same way.
    private var plugins: [String: Plugin] = [:]
    /// Linked opens' landings (`Page.open(_:arg:at:from:how:)`) for the cards not made yet.
    var landings: [String: String] = [:]
    /// The web cards in this window's view.
    private var webInView: Set<String> = []
    /// Dropped web cards' and chats' last pictures, the latest last, until made again.
    private var pictures: [(id: String, picture: CGImage)] = []
    /// Chat cards' pictures from their views in the window (`ChatProbe`), by terminal id.
    var chatViews: [String: () -> CGImage?] = [:]
    /// The terminals in view at the last `show`: a chat among them that left takes its picture.
    private var shownIDs: Set<String> = []

    init() {
        _ = Self.pressure
    }

    /// The pane's terminal, made on first use.
    func terminal(_ terminalID: String, pane paneID: String, client: any Multiplexer) -> PaneTerminal {
        if let terminal = terminals[terminalID] {
            // A moved pane keeps its terminal under a new pane id.
            terminal.paneID = paneID
            return terminal
        }
        let terminal = PaneTerminal(terminalID: terminalID, paneID: paneID, client: client)
        terminal.view.onKeyboard = claim(terminalID)
        terminal.view.onReturn = { [weak self] in self?.pages?.returned(terminalID) }
        terminal.onInput = { [weak self] in self?.pages?.input(terminalID) }
        terminal.watches = { [weak self] in self?.pages?.page(of: terminalID)?.watched ?? false }
        terminal.view.store = { [weak self] in self?.pages?.page(of: terminalID)?.store }
        terminal.view.tileScale = { [weak self] in self?.pages?.tileScale ?? 0.35 }
        terminals[terminalID] = terminal
        return terminal
    }

    /// The browser pane's card, made on first use from its label.
    func browser(_ pane: HostStore.Pane, _ label: PaneLabel, terminalID: String, store: HostStore) -> Browser {
        // Made again for another iid: its state file is another's.
        if let browser = browsers[terminalID], browser.label.iid == label.iid {
            // Only a change: Observation reports equal writes too, and every card body asks.
            if browser.paneID != pane.id {
                browser.paneID = pane.id
                browser.view.setAccessibilityIdentifier("browser.\(pane.id)")
            }
            return browser
        }
        let browser = Browser(terminalID: terminalID, paneID: pane.id, label: label, store: store)
        browser.view.onKeyboard = claim(terminalID)
        browser.view.shot.image = keptPicture(terminalID)
        browsers[terminalID] = browser
        return browser
    }

    /// The plugin pane's card, made on first use from its label.
    func plugin(_ pane: HostStore.Pane, _ label: PaneLabel, terminalID: String, store: HostStore) -> Plugin {
        if let plugin = plugins[terminalID], plugin.label.iid == label.iid {
            if plugin.paneID != pane.id {
                plugin.paneID = pane.id
            }
            return plugin
        }
        let plugin = Plugin(terminalID: terminalID, paneID: pane.id, label: label,
                            place: landings.removeValue(forKey: terminalID), store: store)
        plugin.web.view.onKeyboard = claim(terminalID)
        plugin.web.view.shot.image = keptPicture(terminalID)
        plugin.web.open = { [weak self] kind, arg, place, how in
            let page = self?.pages?.page(of: terminalID)
            Task { await page?.open(kind, arg: arg, at: place, from: terminalID, how: how) }
        }
        plugins[terminalID] = plugin
        return plugin
    }

    /// Cards whose label got another address from elsewhere load it (`Browser.follow`), at each snapshot; a plugin's
    /// card takes its label's new argument.
    /// A card goes with its pane or its label (a rename that breaks it, another iid): its page, timers and proxy share
    /// stop with it.
    private func follow(_ alive: Set<String>) {
        pictures.removeAll { !alive.contains($0.id) }
        chatViews = chatViews.filter { alive.contains($0.key) }
        guard !browsers.isEmpty || !plugins.isEmpty else { return }
        let labels = Dictionary((pages?.withFloats ?? []).flatMap(\.store.panes).compactMap { pane in
            pane.terminalID.flatMap { id in pane.plugin.map { (id, $0) } }
        }, uniquingKeysWith: { first, _ in first })
        // Also a label of another kind with the same iid.
        func kept(_ id: String, _ label: PaneLabel) -> Bool {
            alive.contains(id) && labels[id].map { $0.iid == label.iid && $0.kind == label.kind } == true
        }
        browsers = browsers.filter { kept($0.key, $0.value.label) }
        plugins = plugins.filter { kept($0.key, $0.value.label) }
        for (terminalID, plugin) in plugins {
            if let label = labels[terminalID], label != plugin.label {
                plugin.follow(label)
            }
        }
        for (terminalID, browser) in browsers {
            if let label = labels[terminalID] {
                browser.follow(label.arg)
            }
        }
    }

    /// A terminal, browser or plugin view took the keyboard: the newest holder. A view that had the keyboard before
    /// must not take it back when SwiftUI moves it to a new host (`viewWillMove`). A floating window's (alone in it)
    /// drops none.
    private func claim(_ terminalID: String) -> () -> Void {
        { [weak self] in
            guard let self, pages?.floats(terminalID) != true else { return }
            dropClaims(but: terminalID)
            pages?.current?.tookKeyboard(terminalID)
        }
    }

    /// The browser card of this terminal id, if made.
    func built(_ terminalID: String) -> Browser? {
        browsers[terminalID]
    }

    /// The plugin card of this terminal id, if made.
    func builtPlugin(_ terminalID: String) -> Plugin? {
        plugins[terminalID]
    }

    /// Streams and draws these terminals (terminal id → pane id); past the `spare` most recently shown others,
    /// the rest let go. `unvisited` stream and draw too but are no visit (the overview): they keep their place in
    /// `recent`, and one not in it lets go once no longer shown. Drops the terminals not in `alive` (their panes
    /// closed). The others keep their last picture (a swipe shows the neighbor's). `web`: the web cards in view.
    func show(_ shown: [String: String], web: Set<String>, unvisited: [String: String] = [:], alive: Set<String>,
              client: (any Multiplexer)?)
    {
        // A web card's placeholder is no terminal to stream.
        let shown = shown.filter { !web.contains($0.key) }
        for id in shownIDs.subtracting(shown.keys) {
            if let picture = chatViews[id]?() {
                keep(id, picture)
            }
        }
        shownIDs = Set(shown.keys)
        for (terminalID, terminal) in terminals where !alive.contains(terminalID) {
            terminal.close()
            terminals[terminalID] = nil
            Self.recent.removeAll { $0 === terminal }
            PaneTerminal.snapshots.removeAll { $0 === terminal }
        }
        follow(alive)
        // Without a client (the page in view connecting), the terminals there go on: another page's floated ones.
        let make = { (ids: [String: String]) in
            ids.compactMap { id, pane in client.map { self.terminal(id, pane: pane, client: $0) } ??
                self.terminals[id]
            }
        }
        let visited = make(shown), streaming = visited + make(unvisited)
        for terminal in terminals.values {
            let was = terminal.inView
            terminal.inView = streaming.contains { $0 === terminal }
            // Shown by the overview alone: back to how it was, with no picture (only its snapshot).
            if was, !terminal.inView, !Self.recent.contains(where: { $0 === terminal }) {
                terminal.hide()
                terminal.view.dropPicture()
            }
        }
        Self.recent = Self.recent.filter { terminal in !visited.contains { $0 === terminal } } + visited
        streaming.forEach { $0.show() }
        showWeb(web)
    }

    /// The terminals of these terminal ids that this window has.
    func terminals(_ ids: Set<String>) -> [PaneTerminal] {
        ids.compactMap { terminals[$0] }
    }

    /// Gives the keyboard to this terminal. A view that left the window with the keyboard
    /// would take it back when its tab returns; this one wins instead.
    func focus(_ terminalID: String) {
        dropClaims(but: terminalID)
        // A card that shows its chat: the reply box.
        if let chat = pages?.page(of: terminalID)?.store.chats[terminalID], chat.showsChat, chat.live, !chat.drawer {
            chat.wantsKeyboard = true
            return
        }
        terminals[terminalID]?.view.takeKeyboard()
        browsers[terminalID]?.takeKeyboard()
        plugins[terminalID]?.web.view.takeKeyboard()
    }

    /// Per window: a floating window's terminals keep their claims.
    private func dropClaims(but terminalID: String) {
        for (id, terminal) in terminals where id != terminalID && pages?.floats(id) != true {
            terminal.view.dropClaim()
        }
        for (id, browser) in browsers where id != terminalID && pages?.floats(id) != true {
            browser.dropClaim()
        }
        for (id, plugin) in plugins where id != terminalID && pages?.floats(id) != true {
            plugin.web.view.dropClaim()
        }
    }

    /// The main window's terminal that has the keyboard, from the window itself, so it cannot drift.
    var keyboardTerminalID: String? {
        let views = terminals.mapValues { $0.view as NSView }.merging(browsers.mapValues(\.view)) { first, _ in first }
            .merging(plugins.mapValues(\.web.view)) { first, _ in first }
        return views.first { pages?.floats($0.key) != true && $0.value.window?.firstResponder === $0.value }?.key
    }
}

extension WindowPages {
    /// The web cards in view: the shown tab's and every page's floated ones.
    var webInView: Set<String> {
        Set(withFloats.flatMap { page in
            page.store.panes.filter { $0.plugin != nil && (page === current && $0.tabID == page.selectedTab?.id
                    || page.floats($0)) }.compactMap(\.terminalID)
        })
    }
}

/// The web cards' budget and the cards' pictures.
extension PaneViewRegistry {
    /// The web cards in view now: the ones that left keep a picture, the ones that came show theirs until drawn; past
    /// the `spareWeb` most recently shown others, the oldest are dropped.
    private func showWeb(_ shown: Set<String>) {
        for id in webInView.subtracting(shown) {
            webView(id)?.takePicture()
        }
        for id in shown.subtracting(webInView) {
            webView(id)?.coverUntilDrawn()
        }
        // Once the strip scrolled to them: WebKit hears of its view's place in the window only from its own frame or
        // window, so a page the lazy strip made before a jump to it painted one page off (blank, on CI).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            for id in shown {
                // ponytail: deprecated but still WebKit's hook (`WebViewImpl::renewGState` updates its frames).
                self?.webView(id)?.perform(NSSelectorFromString("renewGState"))
            }
        }
        // Also the ones made since the last call (a card is made as its page draws).
        let touched = webInView.union(shown).filter { webView($0) != nil }
        webInView = shown
        Self.recentWeb.removeAll { kept in
            kept.registry == nil || kept.registry === self && (touched.contains(kept.id) || webView(kept.id) == nil)
        }
        // A card made out of view (a page the lazy strip keeps): the oldest.
        let tracked = Set(Self.recentWeb.filter { $0.registry === self }.map(\.id)).union(touched)
        let untracked = Set(browsers.keys).union(plugins.keys).subtracting(tracked)
        Self.recentWeb = untracked.map { Kept(registry: self, id: $0) } + Self.recentWeb
            + touched.sorted { shown.contains($1) && !shown.contains($0) }.map { Kept(registry: self, id: $0) }
        Self.trim(terminals: Self.spare, web: Self.spareWeb)
    }

    /// Down to these many kept cards out of view: the least recently shown go.
    private static func trim(terminals: Int, web: Int) {
        while recent.count(where: { !$0.inView }) > terminals, let index = recent.firstIndex(where: { !$0.inView }) {
            recent.remove(at: index).hide()
        }
        let droppable = { (kept: Kept) in kept.registry?.droppable(kept.id) == true }
        while recentWeb.count(where: droppable) > web, let index = recentWeb.firstIndex(where: droppable) {
            let kept = recentWeb.remove(at: index)
            kept.registry?.drop(kept.id)
        }
    }

    /// Out of view, not floating, and with no unsaved edits.
    private func droppable(_ id: String) -> Bool {
        !webInView.contains(id) && pages?.floats(id) != true && plugins[id]?.dirty != true && webView(id) != nil
    }

    /// The card goes; its picture stays for its tile and its next card. One with no picture yet (the one asked as it
    /// left view is not there) takes one; the snapshot's reply keeps the web view
    /// until then.
    private func drop(_ id: String) {
        let view = webView(id)
        browsers[id] = nil
        plugins[id] = nil
        if let picture = view?.shot.image {
            return keep(id, picture)
        }
        view?.takePicture { [weak self] picture in
            withExtendedLifetime(view) {}
            // Not for a card made again meanwhile.
            if self?.webView(id) == nil {
                self?.keep(id, picture)
            }
        }
    }

    /// A dropped web card's or a chat's picture, while its pane is there; 200 MB of them at most per window.
    private func keep(_ id: String, _ picture: CGImage) {
        guard pages?.withFloats.contains(where: { $0.store.panes.contains { $0.terminalID == id } }) == true
        else { return }
        pictures.removeAll { $0.id == id }
        pictures.append((id, picture))
        while pictures.reduce(0, { $0 + $1.picture.bytesPerRow * $1.picture.height }) > 200 << 20 {
            pictures.removeFirst()
        }
    }

    private func keptPicture(_ id: String) -> CGImage? {
        pictures.firstIndex { $0.id == id }.map { pictures.remove(at: $0).picture }
    }

    private func webView(_ id: String) -> BrowserView? {
        browsers[id]?.view ?? plugins[id]?.web.view
    }

    /// Pictures of these cards' terminals and web cards as they are now (the overview opens).
    func takePictures(of ids: [String]) {
        for id in ids {
            terminals[id]?.takeSnapshot()
            webView(id)?.takePicture()
            if let picture = chatViews[id]?() {
                keep(id, picture)
            }
        }
    }

    /// The web card's or chat's last picture: its overview tile.
    func picture(_ id: String) -> CGImage? {
        webView(id)?.shot.image ?? pictures.last { $0.id == id }?.picture
    }
}
