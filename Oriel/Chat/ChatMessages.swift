import HerdrKit
import SwiftUI

/// The chat's messages, with the question card and the reply box over their bottom (ui/chat-view#what-it-looks-like).
/// Its own view, so a key typed in the reply box or a card resized does not build the rows again.
struct ChatMessages: View, Equatable {
    let chat: Chat
    let page: Page
    /// In a floating window: the card starts right under its title row, with no header of its own above.
    let floats: Bool
    var composing: FocusState<Bool>.Binding
    /// Where the rows are, and the one at the top of the view.
    @State private var tops = Tops()
    /// The newest message is in view.
    @State private var atBottom = true
    /// Scrolled up from the exact bottom, where the anchor no longer holds the chat.
    @State private var away = false
    /// The card's width the messages lay out at, and the wait for its next one.
    @State private var width: CGFloat?
    @State private var settling: Task<Void, Never>?
    /// The oldest row shown, kept once the chat left the bottom or Show Earlier moved it up, until the card shows its
    /// TUI or a new chat starts; nil: the newest `block` rows.
    @State private var first: String?
    /// Show Earlier's rows are on their way: its spinner shows.
    @State private var earlier = false
    /// The offset the row at the top asks for. Only asked, never told: a place the scroll view names as a scroll
    /// begins or ends, given back to it, snaps that row to the top, a jump past the fingers.
    @State private var position = ScrollPosition(idType: String.self)
    @Environment(\.look) private var look
    private static let end = "end"
    fileprivate nonisolated static let space = "chat.messages"
    /// The rows a long chat shows at a time, and Show Earlier adds. A split lays them out once, at its end: 40 rows of
    /// long replies took one frame of 40–50 ms, 100 rows one of 110–160 ms. With every reply shown, 34 rows lay out in
    /// the time 40 rows of last replies did (the open's worst frame on a 117 MB session: 120 ms; 40 rows: 141 ms).
    private static let block = 34

    init(chat: Chat, page: Page, floats: Bool, composing: FocusState<Bool>.Binding) {
        self.chat = chat
        self.page = page
        self.floats = floats
        self.composing = composing
    }

    /// The focus binding stays the same for a card. Not built again for the store's other changes: the rows are
    /// worked out in the body (3–4 ms for a 3,900-entry history).
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chat === rhs.chat && lhs.page === rhs.page && lhs.floats == rhs.floats
    }

    var body: some View {
        Group {
            // No scroll view until there is something to show: one made empty keeps the top inset that held its empty
            // content at the bottom after a long history loads, a blank above the messages.
            if chat.history.entries.isEmpty, chat.loading || (chat.outgoing.isEmpty && chat.problem == nil) {
                empty
            } else {
                messages
            }
        }
        // The reply box is glass over the messages' bottom, which scroll under it and clear of it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chat.drawer {
                VStack(spacing: 8) {
                    if let question = chat.question, chat.phase == .waiting {
                        QuestionCard(question: question, paneID: chat.paneID) { chat.answer($0) }
                            .disabled(question.answered)
                            .id(question.raw)
                    }
                    Composer(chat: chat, composing: composing)
                }
                // The box's text on the messages' edges: the box reaches past them by its own padding.
                .padding(.horizontal, 32 - Composer.inset).padding(.bottom, 14).padding(.top, 4)
                .frame(maxWidth: ChatView.column).frame(maxWidth: .infinity)
            }
        }
        // The messages fade in under the header instead of being cut by it.
        .fadeEdges(.vertical, start: 12, end: 0)
    }

    /// A new chat: the agent's program icon, gray, in the middle; the loader while a history loads.
    private var empty: some View {
        ZStack {
            if chat.loading {
                ProgressView().controlSize(.small)
            } else if let pane = page.store.pane(chat.paneID) {
                ProgramGlyph(icon: pane.iconID, letter: pane.letter, size: 64).opacity(0.5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(chat.adapter.name)
                    .accessibilityIdentifier("chat.\(chat.paneID).empty")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The next scroll view starts at the bottom, with the newest rows (a new session too).
        .onAppear {
            (tops, atBottom, away, first, earlier) = (Tops(), true, false, nil, false)
            position = ScrollPosition(idType: String.self)
        }
    }

    private var messages: some View {
        let rows = chat.history.rows(working: chat.phase == .working)
        // A kept row that is gone (a new session behind an outgoing message, a re-read with new ids) is pinned again.
        let kept = first.flatMap { id in rows.firstIndex { $0.id == id } }
        let start = kept ?? Self.start(rows[...])
        // ponytail: once pinned, a chat open for hours lays out every row since; cut it again at the exact bottom if a
        // split's layout gets slow.
        let pin = kept == nil && rows.indices.contains(start) && away
        // The view's state and environment the reader's content draws with, read here: a change of either read inside
        // it does not build it again, only a change of what its closure holds (the Scroll to Bottom button never
        // showed). The chat's observed values are tracked inside.
        let (scrolledUp, loading, laidOut, error, place) = (!atBottom, earlier, width, look.error, position)
        return ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a lazy stack guessed the height of the rows it had not built, by up to four times, and
                // after a split showed a blank where it guessed wrong. `block` keeps the layout short.
                VStack(alignment: .leading, spacing: 10) {
                    if start > 0 {
                        earlierButton(loading: loading) { showEarlier(rows, before: start) }
                    }
                    Rows(chat: chat, rows: rows[start...], tops: tops) { position.scrollTo(y: $0) }
                    ForEach(chat.outgoing) { message in
                        outgoing(message, error: error)
                    }
                    if chat.phase == .working {
                        // A message on its way starts a turn the history does not have yet.
                        WorkingRow(since: chat.outgoing.isEmpty ? chat.history.lastTurnStart : nil)
                    }
                    if let problem = chat.problem {
                        problemCard(problem, error: error)
                    }
                    // The end, with the room above the reply box (with the stack's spacing): Scroll to Bottom lands
                    // where a chat opens.
                    Color.clear.frame(height: 22).id(Self.end)
                }
                // While earlier rows exist, Show Earlier's row holds the top padding.
                .padding(.horizontal, 32).padding(.top, start > 0 ? 0 : floats ? 28 : 16)
                .frame(maxWidth: ChatView.column)
                .frame(maxWidth: .infinity)
                .coordinateSpace(.named(Self.space))
            }
            .scrollPosition(.constant(place))
            // Once the chat leaves the bottom: what it shows stays, so no new row takes the held row off the top.
            .task(id: pin) {
                if pin {
                    first = rows[start].id
                }
            }
            // The one rule for the bottom: the chat opens there, and right at the bottom it stays there as rows come
            // and the card resizes. Scrolled up, even by a point, it keeps its offset.
            .defaultScrollAnchor(.bottom)
            // The row at the top as the view moves: at a new width or Show Earlier this runs before the rows report
            // their new places. x: how far the bottom is out of view; at 0 the anchor holds the bottom instead.
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                CGRect(x: geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY,
                       y: geometry.contentOffset.y, width: 0, height: geometry.contentSize.height)
            } action: { old, new in
                // The rows' new height can move the offset in the same update (a wider card's shorter content, clamped
                // at the end): the place is the one before.
                let place = old.height == new.height ? new : old
                tops.hold(at: place.minY, bottom: place.minX <= 0.5)
                // Only a scroll moves it: during a load an update can report the grown rows before the anchor follows.
                if old.height == new.height, away != (new.minX > 0.5) {
                    away = new.minX > 0.5
                }
                if old.height != new.height {
                    earlier = false
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY < 40
            } action: {
                atBottom = $1
            }
            .focusEffectDisabled()
            .accessibilityIdentifier("chat.\(chat.paneID)")
            // The card's new width once it stops changing for 150 ms (a split's motion, a divider or window drag), as
            // a terminal's (SettlingHost): the rows wrap again once, not at every frame. Meanwhile the card clips
            // them, or its fill shows beside them; the reply box, the button and the glyph follow the card at once.
            // At once while the reading column keeps its width.
            .frame(width: laidOut)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                settling?.cancel()
                guard let old = width, min(old, new) < ChatView.column + 64 else {
                    width = new
                    return
                }
                settling = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled {
                        width = new
                    }
                }
            }
            // After the messages' id, which would replace its own.
            .overlay(alignment: .bottom) {
                if scrolledUp {
                    bottomButton { proxy.scrollTo(Self.end, anchor: .bottom) }
                }
            }
        }
    }

    /// The first of the newest `block` rows, at a user's message near there so its turn shows whole.
    private static func start(_ rows: ArraySlice<ChatRow>) -> Int {
        let cut = max(rows.startIndex, rows.endIndex - block)
        guard cut > rows.startIndex else { return cut }
        let user = rows[cut...].prefix(block / 2).firstIndex {
            if case .user = $0 {
                true
            } else {
                false
            }
        }
        return user ?? cut
    }

    /// Down to the newest message, over the messages' bottom: above the reply box.
    private func bottomButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .help("Scroll to Bottom")
        .accessibilityLabel("Scroll to Bottom")
        .accessibilityIdentifier("chat.\(chat.paneID).bottom")
        .padding(.bottom, 10)
    }

    /// The block of rows before `start`. The spinner draws first: the run loop turn after its commit lays the rows
    /// out, which holds the main thread.
    private func showEarlier(_ rows: [ChatRow], before start: Int) {
        guard !earlier else { return }
        earlier = true
        let id = rows[Self.start(rows[..<start])].id
        // Once, after this turn's commit, as `afterCommit` but before waiting only: a click's tracking loop can exit
        // before the commit. The wake-up runs the next turn without waiting for an event.
        let activity = CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activity, false, Int.max) { _, _ in
            MainActor.assumeIsolated { first = id }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// The next block of rows above, in its own row at the top of the messages; a spinner while they load.
    private func earlierButton(loading: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Show Earlier").opacity(loading ? 0 : 1)
                .overlay {
                    if loading {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 28)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Earlier")
        .accessibilityValue(loading ? "loading" : "")
        .accessibilityIdentifier("chat.\(chat.paneID).earlier")
        .frame(maxWidth: .infinity)
        // The messages' top padding, in the button's row.
        .padding(.top, floats ? 28 : 16)
    }

    /// Sending, dimmed; or "Not sent" with Show TUI.
    private func outgoing(_ message: Chat.Outgoing, error: Color) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            UserBubble(text: message.text, paneID: chat.paneID, sending: true).opacity(message.notSent ? 0.5 : 0.7)
            if message.notSent {
                HStack(spacing: 8) {
                    Text("Not sent").font(.system(size: 11)).foregroundStyle(error)
                        .accessibilityIdentifier("chat.\(chat.paneID).not-sent")
                    Button("Show TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 8)
    }

    private func problemCard(_ problem: String, error: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("The chat cannot read this session", systemImage: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(error)
            Text(problem).font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.\(chat.paneID).problem")
            Button("Show TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                .accessibilityIdentifier("chat.\(chat.paneID).show-terminal")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(error.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

/// Each row's top in the messages as last laid out, and the row at the top of the view with how far the view's top is
/// below the row's top. When rows above it change height (a new width) or come (Show Earlier), that row reports its new
/// top and the view goes back to the same place on it. Not observed: it changes at every scroll frame.
@MainActor
private final class Tops {
    var places: [String: CGFloat] = [:]
    var held: (id: String, by: CGFloat)?

    /// The last row whose top is above `offset`, else the first row; none at the exact bottom, which the anchor holds.
    func hold(at offset: CGFloat, bottom: Bool) {
        let above = places.lazy.filter { $0.value <= offset }
        let row = bottom ? nil : above.max { $0.value < $1.value } ?? places.min { $0.value < $1.value }
        held = row.map { ($0.key, offset - $0.value) }
    }
}

/// The history's rows, with the runs and tool calls clicked open.
private struct Rows: View {
    let chat: Chat
    let rows: ArraySlice<ChatRow>
    let tops: Tops
    /// Scrolls to an offset.
    let restore: (CGFloat) -> Void
    /// Runs clicked open.
    @State private var opened: Set<String> = []
    /// Tool calls opened to their input and output.
    @State private var openTools: Set<String> = []

    var body: some View {
        ForEach(rows) { row in
            ChatRowView(row: row, paneID: chat.paneID, counts: counts(row), steps: steps(row),
                        toggle: { opened.formSymmetricDifference([row.id]) }, opened: openTools,
                        toggleTool: { openTools.formSymmetricDifference([$0]) })
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(ChatMessages.space)).minY } action: { top in
                    tops.places[row.id] = top
                    if let held = tops.held, held.id == row.id {
                        restore(top + held.by)
                    }
                }
                .onDisappear { tops.places[row.id] = nil }
        }
    }

    /// An open run's steps, copied: a slice would hold the history's entries, and each new entry would copy them all.
    /// Kept in bounds, though the rows come from the same history.
    private func steps(_ row: ChatRow) -> [ChatEntry]? {
        guard case let .stack(id, steps) = row, opened.contains(id) else { return nil }
        let entries = chat.history.entries
        return Array(entries[steps.clamped(to: entries.indices)])
    }

    /// Worked out for the rows shown only: a long history has thousands of runs.
    private func counts(_ row: ChatRow) -> String {
        guard case let .stack(_, steps) = row else { return "" }
        let entries = chat.history.entries
        return ChatTool.summary(entries[steps.clamped(to: entries.indices)].compactMap(\.tool))
    }
}
