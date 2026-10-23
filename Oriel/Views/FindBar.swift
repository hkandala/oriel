#if os(macOS)
    import GhosttyTerminal
    import HerdrKit
    import SwiftUI

    /// Find in a pane (⌘F): the pane's recent text from herdr, searched here; a match scrolls herdr's viewport to it,
    /// which every client of the pane shares (design: Find bar). The matches on the screen then are highlighted from
    /// herdr's visible text. One bar per page, on the card it opened on.
    @MainActor @Observable
    final class Find {
        let paneID: String
        var query = "" {
            // The field writes the same text back when it takes the keyboard again (a second ⌘F).
            didSet {
                if query != oldValue {
                    search(last: true)
                }
            }
        }

        /// The lines of each match, top to bottom, a line once per match in it.
        private(set) var matches: [Int] = []
        /// The selected match, in `matches`.
        private(set) var current: Int?
        /// The matches on herdr's screen after the last scroll, for the highlights; the selected one, if shown.
        private(set) var shown: [Hit] = []
        private(set) var shownCurrent: Int?
        /// Return went to the pane since the read: the next step reads again.
        @ObservationIgnored var stale = false
        /// Lowercased: the search is case blind.
        @ObservationIgnored private var lines: [String] = []
        /// The screen's blank rows under its last text, which herdr's recent text leaves out but its offset counts.
        @ObservationIgnored private var blank = 0
        /// herdr's screen height.
        @ObservationIgnored private var rows = 0
        @ObservationIgnored private let store: HostStore
        /// The offset to scroll to next; one `pane.scroll` at a time, the latest wins.
        @ObservationIgnored private var target: Int?
        /// The last frame since the highlights were placed.
        @ObservationIgnored private var lastFrame: ContinuousClock.Instant?
        @ObservationIgnored private var working = false

        init(paneID: String, store: HostStore) {
            self.paneID = paneID
            self.store = store
        }

        /// "3 of 12"; nothing before a query.
        var count: String {
            query.isEmpty ? "" : "\(current.map { $0 + 1 } ?? 0) of \(matches.count)"
        }

        /// The pane's last 5000 lines, read once as the bar opens and again after Return in the pane; herdr's buffer
        /// size, for the blank rows under the text.
        func read() async {
            guard let client = store.client else { return }
            do {
                let text = try await client.recent(paneID, lines: 5000)
                let scroll = try await client.pane(paneID).scroll
                lines = Self.lines(text)
                rows = scroll?.viewportRows ?? 0
                if scroll?.offsetFromBottom == 0 {
                    // herdr's visible text also leaves the blank rows out: the screen's rows less its text.
                    blank = try await max(rows - Self.lines(client.screen(paneID)).count, 0)
                } else {
                    // The buffer less the text; a text cut at 5000 lines cannot tell (taken as a full screen).
                    let total = (scroll?.maxOffsetFromBottom ?? 0) + rows
                    blank = lines.count < 5000 ? max(total - lines.count, 0) : 0
                }
                stale = false
                search(last: false)
            } catch {
                await store.show(Notice(text: error.localizedDescription))
            }
        }

        /// The next match down (1) or up (-1), round the ends.
        func step(_ offset: Int) async {
            if stale {
                await read()
            }
            guard !matches.isEmpty else { return }
            current = ((current ?? 0) + offset + matches.count) % matches.count
            show()
        }

        /// Counts the matches, case blind. A new query selects the last match, nearest the bottom; a read again keeps
        /// the selected one's number.
        private func search(last: Bool) {
            let query = query.lowercased()
            matches = query.isEmpty ? [] : lines.indices.flatMap { index in
                Array(repeating: index, count: lines[index].ranges(of: query).count)
            }
            current = matches.isEmpty ? nil : last ? matches.count - 1 : min(current ?? .max, matches.count - 1)
            if current == nil {
                shown = []
                shownCurrent = nil
            }
            show()
        }

        /// The selected match's distance from herdr's last row.
        private var distance: Int? {
            current.map { lines.count - 1 - matches[$0] + blank }
        }

        /// The match's line centered: its distance from the end, less half the screen.
        private func show() {
            if let distance {
                scroll(max(distance - rows / 2, 0))
            }
        }

        /// The matches on the screen herdr shows now, from its visible text (which leaves out the blank rows at its
        /// end). The selected one is the match nearest the row its line is on: its distance from the end, less herdr's
        /// offset, up from the screen's last row.
        /// ponytail: columns count characters, so a line with wide characters (CJK, emoji) before a match puts its
        /// highlight off; measure cell widths if that matters.
        private func locate(_ client: any Multiplexer) async {
            // Taken before the reads; a query changed meanwhile drops the result (its own scroll locates again).
            let query = query.lowercased(), distance = distance
            guard let distance, !query.isEmpty, let screen = try? await client.screen(paneID),
                  let scroll = try? await client.pane(paneID).scroll, let offset = scroll.offsetFromBottom
            else {
                shown = []
                shownCurrent = nil
                return
            }
            guard self.query.lowercased() == query else { return }
            let screenRows = Self.lines(screen)
            shown = screenRows.indices.flatMap { row in
                screenRows[row].ranges(of: query).map { range in
                    Hit(row: row, column: screenRows[row].distance(from: screenRows[row].startIndex,
                                                                   to: range.lowerBound),
                        length: query.count)
                }
            }
            let expected = (scroll.viewportRows ?? rows) - 1 - (distance - offset)
            shownCurrent = shown.indices.min { abs(shown[$0].row - expected) < abs(shown[$1].row - expected) }
        }

        /// herdr's text ends with a newline; the empty piece after it is not a line.
        private static func lines(_ text: String) -> [String] {
            var lines = text.lowercased().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
            return lines
        }

        struct Hit {
            let row, column, length: Int
        }

        /// 0 scrolls back to the bottom.
        func scroll(_ offset: Int) {
            target = offset
            work()
        }

        /// A frame came: the highlights are placed again 0.3 s after the last frame of a burst (agent TUIs redraw
        /// all the time), after at most 1 s of waiting. Our own scroll's frames place them a second time; harmless.
        func screenChanged() {
            lastFrame = .now
            work()
        }

        /// Scrolls, then places the highlights, one step at a time; what was asked for meanwhile goes after. Not a
        /// `store.write`: no Busy gate between keystrokes, and `locate`'s `pane.get` is the read after it.
        private func work() {
            guard !working, let client = store.client else { return }
            working = true
            Task {
                while target != nil || lastFrame != nil {
                    if let offset = target {
                        target = nil
                        do {
                            try await client.scroll(paneID, offsetFromBottom: offset)
                        } catch {
                            Task { await store.show(Notice(text: error.localizedDescription)) }
                        }
                    } else {
                        // A scroll asked for meanwhile goes at once.
                        let began = ContinuousClock.now
                        while target == nil, let last = lastFrame, .now - last < .milliseconds(300),
                              .now - began < .seconds(1)
                        {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        if target != nil {
                            continue
                        }
                    }
                    lastFrame = nil
                    if target == nil {
                        await locate(client)
                    }
                }
                working = false
            }
        }
    }

    /// The find bar at a card's top right.
    struct FindBar: View {
        let find: Find
        let page: Page
        @FocusState private var focused: Bool

        var body: some View {
            HStack(spacing: 4) {
                TextField("Find", text: Bindable(find).query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .focusSoon($focused)
                    .onSubmit { Task { await find.step(1) } }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        Task { await find.step(-1) }
                        return .handled
                    }
                    .onExitCommand { page.closeFind() }
                    .accessibilityIdentifier("find.field")
                // A fixed slot, so the bar keeps its width as the count changes.
                Text(find.count)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                    .accessibilityIdentifier("find.count")
                IconButton(symbol: "chevron.up", help: "Find Previous", size: 22) { Task { await find.step(-1) } }
                    .accessibilityIdentifier("find.previous")
                IconButton(symbol: "chevron.down", help: "Find Next", key: .findNext, size: 22) {
                    Task { await find.step(1) }
                }
                .accessibilityIdentifier("find.next")
                IconButton(symbol: "xmark", help: "Close", size: 22) { page.closeFind() }
                    .accessibilityIdentifier("find.close")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(width: 320, height: 32)
            .glassEffect()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("find")
            // A second ⌘F while the bar is open: the field again.
            .onChange(of: page.findFocus) { focused = true }
        }
    }

    /// The matches on the terminal's screen: the selected one in the accent at 0.45, the others at 0.2. Cells from the
    /// surface's cell size; the terminal has no padding.
    struct FindHighlights: View {
        let find: Find
        let terminal: PaneTerminal
        @Environment(\.displayScale) private var scale

        var body: some View {
            let metrics = terminal.view.metrics
            let cell = CGSize(width: CGFloat(metrics?.cellWidthPixels ?? 0) / scale,
                              height: CGFloat(metrics?.cellHeightPixels ?? 0) / scale)
            ZStack(alignment: .topLeading) {
                ForEach(Array(find.shown.enumerated()), id: \.offset) { index, hit in
                    Rectangle()
                        .fill(Color.accentColor.opacity(index == find.shownCurrent ? 0.45 : 0.2))
                        .frame(width: cell.width * CGFloat(hit.length), height: cell.height)
                        .offset(x: cell.width * CGFloat(hit.column), y: cell.height * CGFloat(hit.row))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            // For tests: what is lit, not pixels.
            .accessibilityElement()
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("Matches")
            .accessibilityValue(
                "\(find.shown.count) shown, current row \(find.shownCurrent.map { "\(find.shown[$0].row)" } ?? "none")",
            )
            .accessibilityIdentifier("find.highlights")
            // Only while the card shows (a hidden tab's frames place nothing), and a terminal made again gets it too.
            .onAppear { [weak find] in terminal.onFrame = { find?.screenChanged() } }
            .onDisappear { terminal.onFrame = nil }
        }
    }

    extension Page {
        /// ⌘F: the bar on the keyboard card, its field focused; reads the pane's text.
        func openFind() {
            guard let pane = keyboardPane else { return }
            if find?.paneID != pane.id {
                // The keyboard stays where it is: not `closeFind`.
                dropFind()
                let find = Find(paneID: pane.id, store: store)
                self.find = find
                Task { await find.read() }
            }
            findFocus += 1
        }

        /// Esc or ×: the bar closes and the keyboard goes back to the card.
        func closeFind() {
            guard let paneID = find?.paneID else { return }
            dropFind()
            if let pane = store.pane(paneID), pane.tabID == selectedTab?.id {
                go(to: pane)
            }
        }

        /// The bar's card is out of view: another tab, or another card of its tab zoomed.
        var findHidden: Bool {
            guard let find else { return false }
            let tabID = store.pane(find.paneID)?.tabID
            return tabID != selectedTab?.id || zoomedPaneID.map { $0 != find.paneID && store.pane($0)?.tabID == tabID }
                == true
        }

        /// The bar goes and herdr's shared viewport goes back to the bottom; also when its page or window closes.
        func dropFind() {
            find?.scroll(0)
            find = nil
        }
    }
#endif
