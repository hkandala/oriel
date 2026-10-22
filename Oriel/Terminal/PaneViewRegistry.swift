#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import HerdrKit

    /// Owns every pane's terminal of one window's pages, keyed by `terminal_id`, so SwiftUI never destroys
    /// one while the strip scrolls. The shown tab's terminals stream; those of recently shown tabs, of any
    /// page, keep streaming, up to `live` of them over all windows, so coming back to a tab resizes nothing
    /// (design: what streams).
    /// ponytail: keyed by terminal id alone; herdr's ids (`term_` and 14 hex digits, from the clock) did not
    /// repeat across sessions. Key by session too if they ever do.
    @MainActor
    final class PaneViewRegistry {
        /// The design's bound on streaming terminals over all windows (D46).
        static let live = 24
        /// Streaming terminals of every window, the most recently shown last.
        private static var recent: [PaneTerminal] = []
        /// A terminal took the keyboard (its terminal id).
        var onKeyboard: ((String) -> Void)?
        /// The user pressed Return in a terminal (its terminal id).
        var onReturn: ((String) -> Void)?
        /// A key press, paste or click in a terminal.
        var onInput: (() -> Void)?
        /// Whether another window controls the terminal's session (its terminal id).
        var watches: ((String) -> Bool)?
        private var terminals: [String: PaneTerminal] = [:]

        /// The pane's terminal, made on first use.
        func terminal(_ terminalID: String, pane paneID: String, client: any Multiplexer) -> PaneTerminal {
            if let terminal = terminals[terminalID] {
                // A moved pane keeps its terminal under a new pane id.
                terminal.paneID = paneID
                return terminal
            }
            let terminal = PaneTerminal(terminalID: terminalID, paneID: paneID, client: client)
            terminal.view.onKeyboard = { [weak self] in self?.onKeyboard?(terminalID) }
            terminal.view.onReturn = { [weak self] in self?.onReturn?(terminalID) }
            terminal.onInput = { [weak self] in self?.onInput?() }
            terminal.watches = { [weak self] in self?.watches?(terminalID) ?? false }
            terminals[terminalID] = terminal
            return terminal
        }

        /// Streams these terminals (terminal id → pane id); past the `live` most recently shown, the
        /// others let go. Drops the terminals not in `alive` (their panes closed). A surface draws only
        /// while it is in the window (a page in view or next to it, so a swipe shows the neighbor's last
        /// image); libghostty stops drawing one that leaves it.
        func show(_ shown: [String: String], alive: Set<String>, client: (any Multiplexer)?) {
            for (terminalID, terminal) in terminals where !alive.contains(terminalID) {
                terminal.close()
                terminals[terminalID] = nil
                Self.recent.removeAll { $0 === terminal }
            }
            for (terminalID, terminal) in terminals {
                terminal.inView = shown[terminalID] != nil
            }
            guard let client else { return }
            let streaming = shown.map { terminal($0.key, pane: $0.value, client: client) }
            streaming.forEach { $0.inView = true }
            Self.recent = Self.recent.filter { terminal in !streaming.contains { $0 === terminal } } + streaming
            // Only ones no window shows go: a tab with more than `live` panes keeps them all.
            // ponytail: an evicted terminal keeps its surface (its last image) until its pane closes
            // or its page closes.
            while Self.recent.count > Self.live, let index = Self.recent.firstIndex(where: { !$0.inView }) {
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
            terminals.values.forEach { $0.view.dropClaim() }
            terminals[terminalID]?.view.takeKeyboard()
        }

        /// The terminal that has the keyboard, from the window itself, so it cannot drift.
        var keyboardTerminalID: String? {
            terminals.first { $0.value.view.window?.firstResponder === $0.value.view }?.key
        }
    }
#endif
