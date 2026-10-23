#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import HerdrKit
    import Observation

    /// One pane's live terminal: herdr's frames drawn by a libghostty surface (host-managed
    /// backend), with keys, clicks and the wheel going back to herdr.
    @MainActor @Observable
    final class PaneTerminal {
        private(set) var state = State.idle
        /// The terminal view is the first responder: keys go here.
        var hasKeyboard = false
        /// herdr's frames settled once (PTY resized, program redrawn), or a watcher drew: the content fades in then,
        /// not at herdr's first frame (the old screen reflowed at the new size).
        private(set) var ready = false
        @ObservationIgnored private var settling: Task<Void, Never>?
        /// The surface's last grid.
        @ObservationIgnored private var grid: InMemoryTerminalViewport?
        @ObservationIgnored let view = PaneSurfaceView(frame: .zero)
        @ObservationIgnored var paneID: String
        @ObservationIgnored private let terminalID: String
        @ObservationIgnored private let client: any Multiplexer
        @ObservationIgnored private let session: InMemoryTerminalSession
        /// Input not sent yet; it goes out while the stream is live.
        @ObservationIgnored private var pending: [Input] = []
        @ObservationIgnored private var draining: Task<Void, Never>?
        /// A paste libghostty is still writing.
        @ObservationIgnored private var paste: String?
        @ObservationIgnored private var tasks: [Task<Void, Never>] = []
        @ObservationIgnored private var run: Task<Void, Never>?
        @ObservationIgnored private var resizing: Task<Void, Never>?
        @ObservationIgnored private var stream: TerminalStream?
        @ObservationIgnored private var observing = false
        @ObservationIgnored private var shown = false
        /// Counts streams, so a stream that is ending cannot change the state of the next one.
        @ObservationIgnored private var generation = 0
        /// Another window controls the session (D66): a new stream watches.
        @ObservationIgnored var watches: () -> Bool = { false }
        /// A key press, paste or click in the card (D8's triggers), before it is handled.
        @ObservationIgnored var onInput: () -> Void = {}
        /// A frame came (the find bar places its highlights again).
        @ObservationIgnored var onFrame: (() -> Void)?
        /// Shown lately, by its window (the registry): not evicted while it is.
        @ObservationIgnored var inView = false

        init(terminalID: String, paneID: String, client: any Multiplexer) {
            self.terminalID = terminalID
            self.paneID = paneID
            self.client = client
            // libghostty writes on its own IO thread; a stream keeps the order.
            let (texts, text) = AsyncStream<String>.makeStream()
            let (sizes, size) = AsyncStream<InMemoryTerminalViewport>.makeStream()
            session = InMemoryTerminalSession(
                write: { text.yield(String(decoding: $0, as: UTF8.self)) },
                resize: { size.yield($0) },
                suppressesPixelOnlyResizes: true,
            )
            // Pastes leave libghostty framed, and herdr frames them again for the app's own mode.
            session.receive("\u{1B}[?2004h")
            view.terminal = self
            view.controller = Self.controller
            view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
            tasks = [
                Task { for await text in texts {
                    enqueue(.text(text))
                } },
                Task { for await size in sizes {
                    resized(size)
                } },
            ]
        }

        /// The card's tab is shown: stream it. Also retries a stream that failed.
        func show() {
            guard !shown || state.isFailed else { return }
            shown = true
            open()
        }

        /// The card left the recently shown set: let go (D46). It keeps its last image.
        func hide() {
            shown = false
            pending = []
            paste = nil
            end()
        }

        /// The session is going away.
        func close() {
            hide()
            tasks.forEach { $0.cancel() }
        }

        /// Take back: control with `--takeover`.
        func takeBack() {
            open(takeover: true)
        }

        /// Control of the session moved between windows (D66): this window's streams take over, or watch.
        func control(_ controls: Bool) {
            if shown, observing == controls {
                // Keys the old controller had not sent yet do not go out at a later takeover.
                if !controls {
                    pending = []
                    paste = nil
                }
                open(observe: !controls, takeover: controls)
            }
        }

        func keys(_ keys: [String]) {
            enqueue(.keys(keys))
        }

        func mouse(_ action: TerminalStream.MouseAction, _ button: TerminalStream.MouseButton,
                   column: Int, row: Int, modifiers: Int)
        {
            if action == .down {
                onInput()
            }
            if state == .watching, action == .down {
                takeBack()
            } else if state == .live {
                stream?.mouse(action, button, column: column, row: row, modifiers: modifiers)
            }
        }

        func scroll(lines: Int, column: Int, row: Int, modifiers: Int) {
            if state == .live {
                stream?.scroll(lines: lines, column: column, row: row, modifiers: modifiers)
            }
        }

        // MARK: Stream

        private func open(observe: Bool = false, takeover: Bool = false) {
            guard shown, let grid else { return }
            end()
            observing = observe || !takeover && watches()
            let generation = generation
            let previous = run
            run = Task {
                // The last stream ends first, so herdr never sees two of ours on one pane.
                await previous?.value
                guard generation == self.generation else { return }
                let stream: TerminalStream
                do {
                    stream = try await client.terminal(terminalID, cols: Int(grid.columns), rows: Int(grid.rows),
                                                       observe: observing, takeover: takeover)
                } catch {
                    if generation == self.generation {
                        state = .failed(error.localizedDescription)
                    }
                    return
                }
                // Ended while it opened: close it too; the loop below drains it until herdr exits.
                if generation == self.generation {
                    self.stream = stream
                } else {
                    stream.close()
                }
                for await event in stream.events where generation == self.generation {
                    switch event {
                    case let .frame(frame):
                        session.receive(frame.bytes)
                        onFrame?()
                        if state == .idle {
                            started(frame)
                        }
                        if !ready {
                            settle()
                        }
                    case let .closed(reason):
                        self.stream = nil
                        closed(reason)
                    }
                }
            }
        }

        /// The first frame of a stream.
        private func started(_ frame: TerminalStream.Frame) {
            state = observing ? .watching : .live
            // A program that redraws all the time never settles: shown a second later anyway.
            Task {
                try? await Task.sleep(for: .seconds(1))
                ready = true
            }
            // The card may have changed size while the stream opened.
            if let grid, frame.width != grid.columns || frame.height != grid.rows {
                resized(grid)
            }
            drain()
        }

        /// Ends the current stream by closing its stdin. The run goes on until herdr exits, so the next `open`
        /// waits for the pane to be free; a stream still opening closes itself once open.
        private func end() {
            generation += 1
            stream?.close()
            stream = nil
            state = .idle
        }

        private func closed(_ reason: TerminalStream.Closed) {
            // No frame yet: herdr refused the stream at open.
            let refused = state == .idle
            state = .idle
            switch reason {
            case .held:
                // Watch. Take over only if the user typed while a refused control opened; a stream
                // taken over mid-session never takes back by itself (design D8). A new task: `open`
                // waits for this run to end.
                let takeover = refused && !pending.isEmpty
                if !takeover {
                    pending = []
                }
                // Not when control moved between windows meanwhile (`control`).
                Task { [generation] in
                    if generation == self.generation {
                        open(observe: !takeover, takeover: takeover)
                    }
                }
            case .liveUpdate:
                // Opens the stream again after 1 s (talking-to-herdr#how-a-stream-ends): a watcher stays one (D8).
                Task { [generation, observing] in
                    try? await Task.sleep(for: .seconds(1))
                    if generation == self.generation {
                        open(observe: observing)
                    }
                }
            case .ended:
                // Gone: the next snapshot drops the card.
                pending = []
            case let .failed(text):
                pending = []
                state = .failed(text)
            }
        }

        // MARK: Size and input

        /// libghostty's grid for the card's size, taken once the layout settles (100 ms after the last change):
        /// a window drag does not make the app repaint at every step, and the first stream opens at the card's
        /// real size, not at the surface's first guess before layout (50×17), which made an agent redraw twice.
        private func resized(_ size: InMemoryTerminalViewport) {
            resizing?.cancel()
            resizing = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                let first = grid == nil
                grid = size
                if first {
                    open()
                } else if state == .watching {
                    // observe cannot resize: watch again at the new size.
                    open(observe: true)
                } else if state == .live {
                    stream?.resize(cols: Int(size.columns), rows: Int(size.rows),
                                   cellWidth: Int(view.metrics?.cellWidthPixels ?? 0),
                                   cellHeight: Int(view.metrics?.cellHeightPixels ?? 0))
                }
            }
        }

        /// libghostty writes a paste in pieces (start mark, text, end mark); herdr frames it for the
        /// app's paste mode only when one write is the whole `ESC[200~…ESC[201~`.
        private func enqueue(_ input: Input) {
            if case let .text(text) = input, paste != nil || text.hasPrefix("\u{1B}[200~") {
                let whole = (paste ?? "") + text
                paste = whole
                // Text after the end mark (typing in the same write) goes out on its own.
                if let end = whole.range(of: "\u{1B}[201~") {
                    paste = nil
                    queue(.text(String(whole[..<end.upperBound])))
                    if end.upperBound < whole.endIndex {
                        queue(.text(String(whole[end.upperBound...])))
                    }
                }
            } else {
                queue(input)
            }
        }

        /// A bridge call takes about 60 ms, more than a held key's repeat, so keys that pile up
        /// meanwhile go as one call; text stays one write per piece, so a paste stays whole.
        /// ponytail: keys (main thread) and libghostty's text (its IO thread) are ordered only as
        /// they arrive here, microseconds apart; enough for typing.
        private func queue(_ input: Input) {
            // A failed card shows why; typing there goes nowhere.
            guard !state.isFailed else { return }
            if case let (.keys(old)?, .keys(new)) = (pending.last, input) {
                pending[pending.count - 1] = .keys(old + new)
            } else {
                pending.append(input)
            }
            onInput()
            if state == .watching {
                takeBack()
            }
            drain()
        }

        /// Sends input in order, one at a time, while the stream is live: a key waits for herdr's
        /// answer before the next text goes out. Input typed before the first frame waits for it.
        private func drain() {
            guard draining == nil else { return }
            draining = Task {
                while state == .live, let stream, !pending.isEmpty {
                    switch pending.removeFirst() {
                    case let .text(text):
                        stream.input(text)
                    case let .keys(keys):
                        try? await client.sendKeys(keys, pane: paneID)
                    }
                }
                draining = nil
            }
        }
    }

    extension PaneTerminal {
        enum State: Equatable {
            /// No stream: not shown lately (D46), closed, or the pane is gone.
            case idle
            case live
            /// Another client controls the pane: watch until the user acts (design D8).
            case watching
            case failed(String)

            var isFailed: Bool {
                guard case .failed = self else { return false }
                return true
            }
        }

        enum Input {
            /// Bytes from libghostty: typed text, IME, pastes.
            case text(String)
            /// herdr logical keys, encoded by herdr for the app's input modes.
            case keys([String])
        }

        /// Ready once frames stop for 100 ms (a watcher cannot resize: at once).
        private func settle() {
            settling?.cancel()
            guard !observing else {
                ready = true
                return
            }
            settling = Task {
                try? await Task.sleep(for: .milliseconds(100))
                if !Task.isCancelled {
                    ready = true
                }
            }
        }
    }

    /// The text size and the one configuration every surface shares.
    extension PaneTerminal {
        /// The text size setting (design: theme and accessibility).
        static let fontSize = 13
        static let fontSizes = 8 ... 32

        /// `keybind = clear`: app shortcuts reach the menu. Transparent, so the card shows through.
        /// No padding, so cells map from the view's origin; no scrollback, herdr keeps it. The system
        /// monospaced font (SF Mono) rather than libghostty's own JetBrains Mono.
        private static let controller = TerminalController(theme: theme) {
            $0.withCustom("keybind", "clear")
            $0.withFontFamily(NSFont.monospacedSystemFont(ofSize: 0, weight: .regular).familyName ?? "Menlo")
            $0.withBackgroundOpacity(0)
            $0.withWindowPaddingX(0)
            $0.withWindowPaddingY(0)
            $0.withCustom("window-padding-balance", "false")
            $0.withCustom("scrollback-limit", "0")
            // Option types characters on every layout (on CI's, libghostty sent Alt by default).
            $0.withCustom("macos-option-as-alt", "false")
        }

        private static let theme = TerminalTheme(light: terminalApp(dark: false), dark: terminalApp(dark: true))

        /// macOS Terminal's look: text near-black on light cards and near-white on dark ones, and Terminal.app's
        /// 16 ANSI colors. ANSI white (7, 15) on light and black (0) on dark are grays that stay readable on the
        /// card, where Terminal.app's own would vanish.
        private static func terminalApp(dark: Bool) -> TerminalConfiguration {
            let palette = ["000000", "C23621", "25BC24", "ADAD27", "492EE1", "D338D3", "33BBC8", "CBCCCD",
                           "818383", "FC391F", "31E722", "EAEC23", "5833FF", "F935F8", "14F0F0", "E9EBEB"]
            let readable = dark ? [0: "6E6E6E"] : [7: "8C8C8C", 15: "6B6B6B"]
            return TerminalConfiguration { builder in
                builder.withForeground(dark ? "E6E6E6" : "1F1F1F")
                builder.withBackground(dark ? "1E1E1E" : "F6F6F6")
                builder.withCursorColor(dark ? "E6E6E6" : "1F1F1F")
                builder.withSelectionBackground(dark ? "3F638B" : "B4D5FE")
                for (index, color) in palette.enumerated() {
                    builder.withPalette(index, color: "#" + (readable[index] ?? color))
                }
            }
        }

        /// Bigger or Smaller, from the stored value: the key monitor in `OrielApp.init` has no `@AppStorage`.
        static func stepFontSize(_ step: Int) {
            let defaults = UserDefaults.standard
            let size = clamped(defaults.object(forKey: "fontSize") as? Int ?? fontSize) + step
            defaults.set(clamped(size), forKey: "fontSize")
        }

        /// Every surface takes a new text size at once, and its stream stays open; its grid changes, so the
        /// card resizes its PTY.
        static func setFontSize(_ size: Int) {
            controller.setTerminalConfiguration(TerminalConfiguration { $0.withFontSize(Float(clamped(size))) })
        }

        /// In 8–32: a hand-edited default (`defaults write`) can be out of range.
        private static func clamped(_ size: Int) -> Int {
            min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
        }
    }
#endif
