#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import HerdrKit

    /// Owns every pane's terminal of one window's pages, keyed by `terminal_id`, so SwiftUI never destroys
    /// one while the strip scrolls. The shown tab's terminals stream; those of recently shown tabs, of any
    /// page, keep streaming, up to `live` of them, so coming back to a tab resizes nothing (design: what
    /// streams).
    /// ponytail: keyed by terminal id alone; herdr's ids (`term_` and 14 hex digits, from the clock) did not
    /// repeat across sessions. Key by session too if they ever do.
    @MainActor
    final class PaneViewRegistry {
        /// The design's bound on streaming terminals (D46).
        static let live = 24
        /// A terminal took the keyboard (its terminal id).
        var onKeyboard: ((String) -> Void)?
        /// The user pressed Return in a terminal (its terminal id).
        var onReturn: ((String) -> Void)?
        private var terminals: [String: PaneTerminal] = [:]
        /// Streaming terminals, the most recently shown last.
        private var recent: [String] = []

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
            }
            recent = recent.filter { alive.contains($0) && shown[$0] == nil } + Array(shown.keys)
            // Only hidden ones go: a tab with more than `live` panes keeps them all.
            // ponytail: an evicted terminal keeps its surface (its last image) until its pane closes
            // or its page closes.
            while recent.count > Self.live, let terminalID = recent.first, shown[terminalID] == nil {
                recent.removeFirst()
                terminals[terminalID]?.hide()
            }
            guard let client else { return }
            for (terminalID, paneID) in shown {
                terminal(terminalID, pane: paneID, client: client).show()
            }
        }

        /// Gives the keyboard to this terminal. A view that left the window with the keyboard
        /// would take it back when its tab returns; this one wins instead.
        func focus(_ terminalID: String) {
            terminals.values.forEach { $0.view.wantsKeyboard = false }
            terminals[terminalID]?.view.takeKeyboard()
        }

        /// The terminal that has the keyboard, from the window itself, so it cannot drift.
        var keyboardTerminalID: String? {
            terminals.first { $0.value.view.window?.firstResponder === $0.value.view }?.key
        }
    }
#endif
