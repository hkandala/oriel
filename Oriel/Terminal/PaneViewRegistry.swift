#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import HerdrKit

    /// Owns every pane's terminal of one window's pages, keyed by `terminal_id`, so SwiftUI never destroys
    /// one while the strip scrolls. The shown tab's terminals stream and draw; the `spare` most recently shown others,
    /// over all windows, keep streaming and their surface without drawing, so coming back to them is at once; the rest
    /// keep only their last picture (design: what streams).
    /// ponytail: keyed by terminal id alone; herdr's ids (`term_` and 14 hex digits, from the clock) did not
    /// repeat across sessions. Key by session too if they ever do.
    @MainActor
    final class PaneViewRegistry {
        /// The design's bound on terminals streaming out of view, over all windows (D46). Each keeps a herdr run and
        /// libghostty's three IOSurfaces (52 MB for a full-window card on a Retina screen); one evicted comes back
        /// under its last picture, redrawn within a few hundred ms (phase 25, lane O).
        static let spare = 4
        /// Streaming terminals of every window, the most recently shown last.
        private(set) static var recent: [PaneTerminal] = []
        /// Its window's pages: they hear of the keyboard, Return and input in its terminals.
        weak var pages: WindowPages?
        private var terminals: [String: PaneTerminal] = [:]

        /// The pane's terminal, made on first use.
        func terminal(_ terminalID: String, pane paneID: String, client: any Multiplexer) -> PaneTerminal {
            if let terminal = terminals[terminalID] {
                // A moved pane keeps its terminal under a new pane id.
                terminal.paneID = paneID
                return terminal
            }
            let terminal = PaneTerminal(terminalID: terminalID, paneID: paneID, client: client)
            terminal.view.onKeyboard = { [weak self] in
                // The newest holder: a view that had the keyboard before must not take it back when SwiftUI moves it
                // to a new host (`viewWillMove`). Per window: a floating window's terminal (alone in it) drops none.
                guard self?.pages?.floats(terminalID) != true else { return }
                self?.terminals.forEach {
                    if $0.key != terminalID, self?.pages?.floats($0.key) != true {
                        $0.value.view.dropClaim()
                    }
                }
                self?.pages?.current?.tookKeyboard(terminalID)
            }
            terminal.view.onReturn = { [weak self] in self?.pages?.returned(terminalID) }
            terminal.onInput = { [weak self] in self?.pages?.input(terminalID) }
            terminal.watches = { [weak self] in self?.pages?.page(of: terminalID)?.watched ?? false }
            terminals[terminalID] = terminal
            return terminal
        }

        /// Streams and draws these terminals (terminal id → pane id); past the `spare` most recently shown others,
        /// the rest let go. Drops the terminals not in `alive` (their panes closed). The others keep their last
        /// picture (a swipe shows the neighbor's).
        func show(_ shown: [String: String], alive: Set<String>, client: (any Multiplexer)?) {
            for (terminalID, terminal) in terminals where !alive.contains(terminalID) {
                terminal.close()
                terminals[terminalID] = nil
                Self.recent.removeAll { $0 === terminal }
            }
            // Without a client (the page in view connecting), the terminals there go on: another page's floated ones.
            let streaming = shown.compactMap { id, pane in client.map { terminal(id, pane: pane, client: $0) } ??
                terminals[id]
            }
            for terminal in terminals.values {
                terminal.inView = streaming.contains { $0 === terminal }
            }
            Self.recent = Self.recent.filter { terminal in !streaming.contains { $0 === terminal } } + streaming
            // A remote machine's connection holds about 10 SSH sessions (machines#ssh-sessions): only what is in view
            // streams there.
            if pages?.machine.isRemote == true {
                for terminal in terminals.values
                    where !terminal.inView && Self.recent.contains(where: { $0 === terminal })
                {
                    Self.recent.removeAll { $0 === terminal }
                    terminal.hide()
                }
            }
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
            for (id, terminal) in terminals where pages?.floats(id) != true {
                terminal.view.dropClaim()
            }
            terminals[terminalID]?.view.takeKeyboard()
        }

        /// The main window's terminal that has the keyboard, from the window itself, so it cannot drift.
        var keyboardTerminalID: String? {
            terminals.first { pages?.floats($0.key) != true && $0.value.view.window?.firstResponder === $0.value.view }
                .map(\.key)
        }
    }
#endif
