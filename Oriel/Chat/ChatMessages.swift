import HerdrKit
import SwiftUI

/// The chat's messages, with the question card and the reply box over their bottom (ui/chat-view#what-it-looks-like).
/// Its own view, so a key typed in the reply box or a card resized does not build the rows again.
struct ChatMessages: View, Equatable {
    let chat: Chat
    let page: Page
    var composing: FocusState<Bool>.Binding
    /// While scrolled up, the row at the top, which stays there when the card resizes or rows come; nil at the
    /// bottom, which stays at the bottom.
    @State private var top: String?
    /// The newest message is in view.
    @State private var atBottom = true
    /// The oldest row shown is in view: Show Earlier shows over it.
    @State private var atTop = false
    /// A row holds the place: the scroll view named one since the chat left the bottom. Until then the bottom does,
    /// also scrolled up inside a newest reply taller than the view.
    @State private var held = false
    /// The card's width the messages lay out at, and the wait for its next one.
    @State private var width: CGFloat?
    @State private var settling: Task<Void, Never>?
    /// The oldest row shown, once Show Earlier was clicked; nil: the newest `block` rows.
    @State private var first: String?
    @Environment(\.look) private var look
    private var settings = AppSettings()
    private static let end = "end"
    /// The rows a long chat shows at a time, and Show Earlier adds: about 25 turns, laid out in 0.3–0.4 s on a
    /// very busy Mac.
    static let block = 100

    init(chat: Chat, page: Page, composing: FocusState<Bool>.Binding) {
        self.chat = chat
        self.page = page
        self.composing = composing
    }

    /// The focus binding stays the same for a card.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chat === rhs.chat && lhs.page === rhs.page
    }

    var body: some View {
        Group {
            // No scroll view until there is something to show: one made empty keeps the top inset that held its empty
            // content at the bottom after a long history loads, a blank above the messages.
            if chat.history.entries.isEmpty, chat.outgoing.isEmpty, chat.problem == nil {
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
                ProgressView().controlSize(.small).accessibilityIdentifier("chat.\(chat.paneID).loading")
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
            hold(nil)
            atBottom = true
            first = nil
        }
    }

    private var messages: some View {
        let floats = page.store.pane(chat.paneID).map(page.floats) == true
        let level = settings.chatLevel
        let rows = chat.history.rows(level, working: chat.phase == .working)
        let start = first.flatMap { id in rows.firstIndex { $0.id == id } } ?? Self.start(rows[...])
        return ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a lazy stack guessed the height of the rows it had not built, by up to four times, and
                // after a split showed a blank where it guessed wrong. `block` keeps the layout short.
                VStack(alignment: .leading, spacing: 10) {
                    Rows(chat: chat, rows: rows[start...], level: level)
                    ForEach(chat.outgoing) { message in
                        outgoing(message)
                    }
                    if chat.phase == .working {
                        // A message on its way starts a turn the history does not have yet.
                        WorkingRow(since: chat.outgoing.isEmpty ? chat.history.lastTurnStart : nil)
                    }
                    if let problem = chat.problem {
                        problemCard(problem)
                    }
                    // The end, with the room above the reply box (with the stack's spacing): Scroll to Bottom lands
                    // where a chat opens.
                    Color.clear.frame(height: 22).id(Self.end)
                }
                .scrollTargetLayout()
                // A floating window's card starts right under its title row, with no header of its own above. None
                // above a long chat's oldest row shown: the scroll keeps the row at the top in place, its top at the
                // top, so earlier rows come above it without moving what is in view.
                .padding(.horizontal, 32).padding(.top, start > 0 ? 0 : floats ? 28 : 16)
                .frame(maxWidth: ChatView.column)
                .frame(maxWidth: .infinity)
            }
            // The scroll view names the row at the top as it scrolls: not at the bottom, which follows new rows. Set
            // here, not in an onChange, so the body is not built again per row scrolled past.
            .scrollPosition(id: Binding(get: { top }, set: { hold(atBottom ? nil : $0) }), anchor: .top)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(held ? nil : .bottom, for: .sizeChanges)
            .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.minY < 40 } action: { atTop = $1 }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY < 40
            } action: {
                atBottom = $1
                if $1 {
                    hold(nil)
                }
            }
            .focusEffectDisabled()
            .accessibilityIdentifier("chat.\(chat.paneID)")
            // The card's new width once it stops changing for 150 ms (a split's motion, a divider or window drag), as
            // a terminal's (SettlingHost): the rows wrap again once, not at every frame. Meanwhile the card clips
            // them, or its fill shows beside them; the reply box, the button and the glyph follow the card at once.
            // At once while the reading column keeps its width.
            .frame(width: width)
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
                if !atBottom {
                    bottomButton { proxy.scrollTo(Self.end, anchor: .bottom) }
                }
            }
            .overlay(alignment: .top) {
                if start > 0, atTop {
                    earlierButton { first = rows[Self.start(rows[..<start])].id }.padding(.top, floats ? 28 : 16)
                }
            }
        }
    }

    /// The first of the newest `block` rows, at a user's message so its turn shows whole.
    static func start(_ rows: ArraySlice<ChatRow>) -> Int {
        guard rows.count > block else { return rows.startIndex }
        let cut = rows.endIndex - block
        return rows[cut...].firstIndex {
            if case .user = $0 {
                true
            } else {
                false
            }
        } ?? cut
    }

    /// The row at the top while scrolled up; `held` changes only when that starts or ends, so the body is not built
    /// again per row.
    private func hold(_ row: String?) {
        top = row
        if held != (row != nil) {
            held = row != nil
        }
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

    /// The next block of rows above, over the messages' top.
    private func earlierButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Show Earlier").font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 28)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.\(chat.paneID).earlier")
    }

    /// Sending, dimmed; or "Not sent" with Show TUI.
    private func outgoing(_ message: Chat.Outgoing) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            UserBubble(text: message.text, paneID: chat.paneID, sending: true).opacity(message.notSent ? 0.5 : 0.7)
            if message.notSent {
                HStack(spacing: 8) {
                    Text("Not sent").font(.system(size: 11)).foregroundStyle(look.error)
                        .accessibilityIdentifier("chat.\(chat.paneID).not-sent")
                    Button("Show TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 8)
    }

    private func problemCard(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("The chat cannot read this session", systemImage: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(look.error)
            Text(problem).font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.\(chat.paneID).problem")
            Button("Show TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                .accessibilityIdentifier("chat.\(chat.paneID).show-terminal")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.error.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

/// The history's rows shown at the level, with the stacks and tool calls clicked open.
private struct Rows: View {
    let chat: Chat
    let rows: ArraySlice<ChatRow>
    let level: ChatLevel
    /// Stacks clicked open or closed: they stay so at every level (else open at Everything only).
    @State private var opened: [String: Bool] = [:]
    /// Tool calls opened to their input and output.
    @State private var openTools: Set<String> = []

    var body: some View {
        ForEach(rows) { row in
            let open = opened[row.id] ?? (level == .everything)
            ChatRowView(row: row, paneID: chat.paneID, open: open, toggle: { opened[row.id] = !open },
                        opened: openTools, toggleTool: { openTools.formSymmetricDifference([$0]) })
        }
    }
}
