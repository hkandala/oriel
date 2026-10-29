import AppKit
import GhosttyTerminal
import HerdrKit

/// Owns every pane's terminal of one window's pages, keyed by `terminal_id`, so SwiftUI never destroys
/// one while the strip scrolls. The shown tab's terminals stream and draw; the `spare` most recently shown others,
/// over all windows, keep their surface without drawing (as Ghostty's hidden tabs) and, on this Mac, their
/// stream, so coming back to them is at once; the rest keep only their last picture (design: what streams).
/// ponytail: keyed by terminal id alone; herdr's ids (`term_` and 14 hex digits, from the clock) did not
/// repeat across sessions. Key by session too if they ever do.
@MainActor
final class PaneViewRegistry {
    /// The design's bound on terminals kept out of view, over all windows (D46). Each keeps its surface, about
    /// 6 MB (libghostty frees the swap chain while it does not draw and makes it again in under a millisecond when
    /// shown), a copy of its last picture (17 MB for a full-window card on Retina) and a herdr run of 7 MB. On
    /// Retina: 405 MB with 16 terminals in splits, 653 MB with 33 full-window tabs (190 MB before,
    /// with 4). One evicted comes back under its last picture if the system kept it, else it fades in.
    /// `-spareTerminals N` for tests.
    static let spare = UserDefaults.standard.string(forKey: "spareTerminals").flatMap { Int($0) } ?? 16
    /// Kept terminals of every window (a surface; a stream unless paused), the most recently shown last.
    private(set) static var recent: [PaneTerminal] = []
    /// Its window's pages: they hear of the keyboard, Return and input in its terminals.
    weak var pages: WindowPages?
    private var terminals: [String: PaneTerminal] = [:]
    /// Browser panes' cards (ui/browser), by terminal id as terminals are: a moved card keeps its page.
    private var browsers: [String: Browser] = [:]
    /// The other plugin panes' cards, the same way.
    private var plugins: [String: Plugin] = [:]

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
        browsers[terminalID] = browser
        return browser
    }

    /// The plugin pane's card, made on first use from its label.
    func plugin(_ pane: HostStore.Pane, _ label: PaneLabel, terminalID: String) -> Plugin {
        if let plugin = plugins[terminalID], plugin.label.iid == label.iid {
            if plugin.paneID != pane.id {
                plugin.paneID = pane.id
            }
            return plugin
        }
        let plugin = Plugin(terminalID: terminalID, paneID: pane.id, label: label)
        plugins[terminalID] = plugin
        return plugin
    }

    /// Cards whose label got another address from elsewhere load it (`Browser.follow`), at each snapshot; a plugin's
    /// card takes its label's new argument.
    /// A card goes with its pane or its label (a rename that breaks it, another iid): its page, timers and proxy share
    /// stop with it.
    private func follow(_ alive: Set<String>) {
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
                plugin.label = label
            }
        }
        for (terminalID, browser) in browsers {
            if let label = labels[terminalID] {
                browser.follow(label.arg)
            }
        }
    }

    /// A terminal or browser view took the keyboard: the newest holder. A view that had the keyboard before must not
    /// take it back when SwiftUI moves it to a new host (`viewWillMove`). A floating window's (alone in it) drops none.
    private func claim(_ terminalID: String) -> () -> Void {
        { [weak self] in
            guard let self, pages?.floats(terminalID) != true else { return }
            dropClaims(but: terminalID)
            pages?.current?.tookKeyboard(terminalID)
        }
    }

    /// A plugin card's content took the keyboard: as a terminal's or a browser's view does.
    func claimed(_ terminalID: String) {
        claim(terminalID)()
    }

    /// The browser card of this terminal id, if made.
    func built(_ terminalID: String) -> Browser? {
        browsers[terminalID]
    }

    /// Streams and draws these terminals (terminal id → pane id); past the `spare` most recently shown others,
    /// the rest let go. `unvisited` stream and draw too but are no visit (the overview): they keep their place in
    /// `recent`, and one not in it lets go once no longer shown. Drops the terminals not in `alive` (their panes
    /// closed). The others keep their last picture (a swipe shows the neighbor's).
    func show(_ shown: [String: String], unvisited: [String: String] = [:], alive: Set<String>,
              client: (any Multiplexer)?)
    {
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
        while Self.recent.count(where: { !$0.inView }) > Self.spare,
              let index = Self.recent.firstIndex(where: { !$0.inView })
        {
            Self.recent.remove(at: index).hide()
        }
        streaming.forEach { $0.show() }
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
        plugins[terminalID]?.wantsKeyboard = true
    }

    /// Per window: a floating window's terminals keep their claims.
    private func dropClaims(but terminalID: String) {
        for (id, terminal) in terminals where id != terminalID && pages?.floats(id) != true {
            terminal.view.dropClaim()
        }
        for (id, browser) in browsers where id != terminalID && pages?.floats(id) != true {
            browser.dropClaim()
        }
        for (id, plugin) in plugins where id != terminalID && plugin.wantsKeyboard {
            plugin.wantsKeyboard = false
        }
    }

    /// The main window's terminal that has the keyboard, from the window itself, so it cannot drift.
    var keyboardTerminalID: String? {
        let views = terminals.mapValues { $0.view as NSView }.merging(browsers.mapValues(\.view)) { first, _ in first }
        return views.first { pages?.floats($0.key) != true && $0.value.window?.firstResponder === $0.value }?.key
    }
}
