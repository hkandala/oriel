import HerdrKit
import SwiftUI

/// An agent card's chat (future-work/chat-view#what-it-looks-like): the messages, newest at the bottom, and the reply
/// box; the live terminal in its place while the agent waits on something the chat cannot answer. The pill card is
/// the same view at the Replies level.
struct ChatView: View {
    @Bindable var chat: Chat
    let page: Page
    let terminal: PaneTerminal?
    let level: ChatLevel
    /// A zoomed card: the messages in a reading column.
    var column = false
    /// Stacks clicked open or closed, against the level's default.
    @State private var toggled: Set<String> = []
    @State private var height: CGFloat = 0
    @FocusState private var composing: Bool
    @Environment(\.look) private var look

    var body: some View {
        let id = chat.paneID, working = chat.phase == .working
        let rows = chat.history.rows(level, working: working)
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        ChatRowView(row: row, paneID: id, open: (level == .all) != toggled.contains(row.id)) {
                            toggled.formSymmetricDifference([row.id])
                        }
                    }
                    ForEach(chat.outgoing) { message in
                        outgoing(message)
                    }
                    if working, rows.last.map({
                        if case .summary = $0 {
                            false
                        } else {
                            true
                        }
                    }) ?? true {
                        HStack(spacing: 6) {
                            WorkingDots()
                            Text("Working").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                    }
                    if let problem = chat.problem {
                        problemCard(problem)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: column ? 760 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .focusEffectDisabled()
            .accessibilityIdentifier("chat.\(id)")
            bottom.padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 4)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .task { await chat.viewed() }
        // In place of the terminal that had the keyboard (the chooser's loader went, or the switch flipped).
        .onAppear {
            if page.keyboardPane?.id == chat.paneID {
                chat.wantsKeyboard = true
            }
        }
        .onChange(of: chat.wantsKeyboard, initial: true) {
            // On the next turn: a first responder set during an update is undone.
            if chat.wantsKeyboard {
                chat.wantsKeyboard = false
                Task { composing = true }
            }
        }
        .onChange(of: composing) {
            if composing, let terminalID = page.store.pane(id)?.terminalID {
                page.tookKeyboard(terminalID)
            }
        }
    }

    @ViewBuilder private var bottom: some View {
        if chat.drawer, let terminal {
            WaitingDrawer(chat: chat, page: page, terminal: terminal).frame(height: max(160, height * 0.45))
        } else {
            VStack(spacing: 8) {
                if let question = chat.question, chat.phase == .waiting {
                    QuestionCard(question: question, paneID: chat.paneID) { chat.answer($0) }
                }
                composer
            }
        }
    }

    private var composer: some View {
        let id = chat.paneID, working = chat.phase == .working
        let name = chat.adapter.name
        return HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Reply to \(name)", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 8)
                    .focused($composing)
                    .onSubmit { chat.send(chat.draft) }
                    .accessibilityIdentifier("chat.\(id).composer")
                if let model = chat.history.model {
                    Text(model).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        .accessibilityIdentifier("chat.\(id).model")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 17))
            .contentShape(.rect)
            .onTapGesture { composing = true }
            if working, chat.draft.isEmpty {
                round("stop.fill", help: "Stop", id: "chat.\(id).stop", action: chat.stop)
            } else {
                round("arrow.up", help: "Send", id: "chat.\(id).send") { chat.send(chat.draft) }
                    .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || ![.ready, .working].contains(chat.phase) && !chat.draft.hasPrefix("/"))
            }
        }
    }

    private func round(_ symbol: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }

    /// Sending, dimmed; or "Not sent" with Show Terminal.
    private func outgoing(_ message: Chat.Outgoing) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            UserBubble(text: message.text, paneID: chat.paneID).opacity(message.notSent ? 0.5 : 0.7)
            if message.notSent {
                HStack(spacing: 8) {
                    Text("Not sent").font(.system(size: 11)).foregroundStyle(look.error)
                        .accessibilityIdentifier("chat.\(chat.paneID).not-sent")
                    Button("Show Terminal") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func problemCard(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("The chat cannot read this session", systemImage: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(look.error)
            Text(problem).font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.\(chat.paneID).problem")
            Button("Show Terminal") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                .accessibilityIdentifier("chat.\(chat.paneID).show-terminal")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.error.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

/// The live terminal at the bottom of the card while the agent waits (future-work/chat-view#sending-and-answering):
/// it takes the keyboard, and goes when the agent works or is idle again.
private struct WaitingDrawer: View {
    let chat: Chat
    let page: Page
    let terminal: PaneTerminal
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(look.needsYou).frame(width: 7, height: 7)
                Text("\(chat.adapter.name) is asking in the terminal").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Button("Open Terminal") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                    .accessibilityIdentifier("chat.\(chat.paneID).open-terminal")
            }
            TerminalCard(terminal: terminal, watched: page.watched, alpha: 1)
                .clipShape(.rect(cornerRadius: 6))
        }
        .padding(8)
        .background(look.needsYou.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(look.needsYou.opacity(0.35)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.\(chat.paneID).drawer")
        .onAppear {
            if let terminalID = page.store.pane(chat.paneID)?.terminalID, page.keyboardPane?.id == chat.paneID {
                page.terminals.focus(terminalID)
            }
        }
        // The reply box takes the keyboard back.
        .onDisappear {
            if page.keyboardPane?.id == chat.paneID {
                chat.wantsKeyboard = true
            }
        }
    }
}
