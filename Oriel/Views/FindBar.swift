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
            didSet { search(last: true) }
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
        @ObservationIgnored private let store: HostStore
        /// The card's rows, to center a match.
        @ObservationIgnored private let rows: () -> Int
        /// The offset to scroll to next; one `pane.scroll` at a time, the latest wins.
        @ObservationIgnored private var target: Int?
        /// The screen changed since the highlights were placed.
        @ObservationIgnored private var moved = false
        @ObservationIgnored private var working = false

        init(paneID: String, store: HostStore, rows: @escaping () -> Int) {
            self.paneID = paneID
            self.store = store
            self.rows = rows
        }

        /// "3 of 12"; nothing before a query.
        var count: String {
            query.isEmpty ? "" : "\(current.map { $0 + 1 } ?? 0) of \(matches.count)"
        }

        /// The pane's last 5000 lines, read once as the bar opens and again after Return in the pane.
        func read() async {
            guard let client = store.client else { return }
            do {
                let text = try await client.recent(paneID, lines: 5000)
                // The text ends with a newline.
                lines = text.lowercased().split(separator: "\n", omittingEmptySubsequences: false).dropLast()
                    .map(String.init)
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
            show()
        }

        /// The match's line centered: its distance from the end, less half the screen.
        private func show() {
            if let current {
                scroll(max(lines.count - 1 - matches[current] - rows() / 2, 0))
            }
        }

        /// The matches on the screen herdr shows now, from its visible text. The selected one is the match nearest the
        /// row its line should be on: its distance from the end, less herdr's offset, up from the screen's last line
        /// (at the bottom, the last line with text: herdr's recent text leaves out the blank rows under it).
        /// ponytail: columns count characters, so a line with wide characters (CJK, emoji) before a match puts its
        /// highlight off; measure cell widths if that matters.
        private func locate(_ client: any Multiplexer) async {
            // Taken before the reads: the query may change meanwhile (the next scroll locates again).
            let query = query.lowercased(), distance = current.map { lines.count - 1 - matches[$0] }
            guard let distance, !query.isEmpty, let screen = try? await client.screen(paneID),
                  let offset = try? await client.pane(paneID).scroll?.offsetFromBottom
            else {
                shown = []
                shownCurrent = nil
                return
            }
            let rows = screen.lowercased().split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            shown = rows.indices.flatMap { row in
                rows[row].ranges(of: query).map { range in
                    Hit(row: row, column: rows[row].distance(from: rows[row].startIndex, to: range.lowerBound),
                        length: query.count)
                }
            }
            let bottom = offset > 0 ? rows.count - 1 : rows.lastIndex { !$0.allSatisfy(\.isWhitespace) } ?? 0
            let expected = bottom - (distance - offset)
            shownCurrent = shown.indices.min { abs(shown[$0].row - expected) < abs(shown[$1].row - expected) }
        }

        struct Hit {
            let row, column, length: Int
        }

        /// 0 scrolls back to the bottom.
        func scroll(_ offset: Int) {
            target = offset
            work()
        }

        /// A frame came: the highlights are placed again, once the frames of a burst have come.
        func screenChanged() {
            moved = true
            work()
        }

        /// Scrolls, then places the highlights, one step at a time; what was asked for meanwhile goes after.
        private func work() {
            guard !working, let client = store.client else { return }
            working = true
            Task {
                while target != nil || moved {
                    if let offset = target {
                        target = nil
                        try? await client.scroll(paneID, offsetFromBottom: offset)
                    } else {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    moved = false
                    if target == nil {
                        await locate(client)
                    }
                }
                working = false
            }
        }
    }

    /// The find bar at a card's top right: the field, "3 of 12", previous and next, close.
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
        }
    }

    extension Page {
        /// ⌘F: the bar on the keyboard card, its field focused; reads the pane's text.
        func openFind() {
            guard let pane = keyboardPane else { return }
            if find?.paneID != pane.id {
                closeFind()
                let terminal = terminal(pane)
                let find = Find(paneID: pane.id, store: store) { Int(terminal?.view.metrics?.rows ?? 0) }
                terminal?.onFrame = { [weak find] in find?.screenChanged() }
                self.find = find
                Task { await find.read() }
            }
            findFocus += 1
        }

        /// The bar closes, herdr's viewport goes back to the bottom, and the keyboard goes back to the card.
        func closeFind() {
            guard let find else { return }
            find.scroll(0)
            self.find = nil
            guard let pane = store.pane(find.paneID) else { return }
            terminal(pane)?.onFrame = nil
            if pane.tabID == selectedTab?.id {
                go(to: pane)
            }
        }
    }
#endif
