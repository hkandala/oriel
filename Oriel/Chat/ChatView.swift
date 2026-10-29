import HerdrKit
import SwiftUI

/// An agent card's chat (ui/chat-view#what-it-looks-like).
struct ChatView: View {
    @Bindable var chat: Chat
    let page: Page
    let terminal: PaneTerminal?
    /// The conversation's reading column, as in Messages: a wide card centers it.
    private static let column: CGFloat = 760
    /// The reply box's text from its sides.
    private static let inset: CGFloat = 14
    /// Stacks clicked open or closed: they stay so at every level (else open at Everything only).
    @State private var opened: [String: Bool] = [:]
    /// Tool calls opened to their input and output.
    @State private var openTools: Set<String> = []
    @State private var height: CGFloat = 0
    @FocusState private var composing: Bool
    @Environment(\.look) private var look
    private var settings = AppSettings()

    var body: some View {
        VStack(spacing: 0) {
            messages
            if chat.drawer, let terminal {
                WaitingDrawer(chat: chat, page: page, terminal: terminal).frame(height: max(160, height * 0.45))
                    .padding(.horizontal, 32).padding(.bottom, 14).padding(.top, 4)
                    .frame(maxWidth: Self.column).frame(maxWidth: .infinity)
            }
        }
        // Esc stops the agent while it works, as in its TUI.
        .onExitCommand(perform: chat.stop)
        // A click anywhere, on text too, gives the card the keyboard: the reply box, or the drawer's terminal. A
        // button's or a link's click acts as well. Not a double or triple click or a ⇧-click, which select text (Copy
        // needs it to stay), nor a ⌃-click, which opens the menu.
        .contentShape(.rect)
        .simultaneousGesture(TapGesture().onEnded {
            guard let event = NSApp.currentEvent, event.clickCount < 2,
                  event.modifierFlags.isDisjoint(with: [.shift, .control]) else { return }
            if !chat.drawer {
                composing = true
            } else if let terminalID = page.store.pane(chat.paneID)?.terminalID {
                page.terminals.focus(terminalID)
            }
        })
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .task(id: ObjectIdentifier(chat)) { await chat.viewed() }
        // An answered question goes once the agent goes on (herdr's status; the adapter clears its own).
        .onChange(of: chat.phase) { old, new in
            if old == .waiting, new != .waiting {
                chat.question = nil
            }
        }
        // In place of the terminal that had the keyboard (the chooser's loader went, or the switch flipped).
        .onAppear {
            if page.hasKeyboard(chat.paneID) {
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
            if composing, let terminalID = page.store.pane(chat.paneID)?.terminalID {
                page.tookKeyboard(terminalID)
            }
        }
    }

    private var messages: some View {
        let working = chat.phase == .working, level = settings.chatLevel
        let rows = chat.history.rows(level, working: working)
        let floats = page.store.pane(chat.paneID).map(page.floats) == true
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    let open = opened[row.id] ?? (level == .everything)
                    ChatRowView(row: row, paneID: chat.paneID, open: open, toggle: { opened[row.id] = !open },
                                opened: openTools, toggleTool: { openTools.formSymmetricDifference([$0]) })
                }
                ForEach(chat.outgoing) { message in
                    outgoing(message)
                }
                if working {
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
            // A floating window's card starts right under its title row, with no header of its own above.
            .padding(.horizontal, 32).padding(.top, floats ? 28 : 16).padding(.bottom, 16)
            .frame(maxWidth: Self.column)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .focusEffectDisabled()
        .accessibilityIdentifier("chat.\(chat.paneID)")
        // The reply box is glass over the messages' bottom, which scroll under it and clear of it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chat.drawer {
                VStack(spacing: 8) {
                    if let question = chat.question, chat.phase == .waiting {
                        QuestionCard(question: question, paneID: chat.paneID) { chat.answer($0) }
                            .disabled(question.answered)
                            .id(question.raw)
                    }
                    composer
                }
                // The box's text on the messages' edges: the box reaches past them by its own padding.
                .padding(.horizontal, 32 - Self.inset).padding(.bottom, 14).padding(.top, 4)
                .frame(maxWidth: Self.column).frame(maxWidth: .infinity)
            }
        }
        // The messages fade in under the header instead of being cut by it.
        .fadeEdges(.vertical, start: 12, end: 0)
    }

    private var composer: some View {
        let working = chat.phase == .working
        return VStack(alignment: .leading, spacing: 2) {
            TextField("Ask Anything", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1 ... 10)
                .focused($composing)
                .onSubmit { chat.send(chat.draft) }
                // ⇧Return adds a line, as ⌥Return does.
                .onKeyPress(.return, phases: [.down, .repeat]) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                    return .handled
                }
                // Its text ends as far in as it starts; Send sits closer to the box's side.
                .padding(.trailing, Self.inset - 7)
                .accessibilityIdentifier("chat.\(chat.paneID).composer")
            HStack(spacing: 8) {
                let model = [chat.history.model.map(ChatHistory.modelName), chat.history.effort].compactMap(\.self)
                    .joined(separator: " · ")
                if !model.isEmpty {
                    Text(model).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("chat.\(chat.paneID).model")
                }
                Spacer(minLength: 0)
                if working, chat.draft.isEmpty {
                    roundButton("stop.fill", help: "Stop", id: "chat.\(chat.paneID).stop", action: chat.stop)
                } else {
                    let text = !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let ready = [.ready, .working].contains(chat.phase) || chat.draft.hasPrefix("/")
                    roundButton("arrow.up", help: "Send", id: "chat.\(chat.paneID).send", enabled: text && ready) {
                        chat.send(chat.draft)
                    }
                }
            }
        }
        .padding(.leading, Self.inset).padding(.trailing, 7).padding(.top, 9).padding(.bottom, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture { composing = true }
    }

    private func roundButton(_ symbol: String, help: String, id: String, enabled: Bool = true,
                             action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? AnyShapeStyle(Look.onAccent) : AnyShapeStyle(.tertiary))
                .frame(width: 22, height: 22)
                .background(enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }

    /// Sending, dimmed; or "Not sent" with Show Terminal.
    private func outgoing(_ message: Chat.Outgoing) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            UserBubble(text: message.text, paneID: chat.paneID, sending: true).opacity(message.notSent ? 0.5 : 0.7)
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

/// The live terminal at the bottom of the card while the agent waits (ui/chat-view#waiting).
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
            if let terminalID = page.store.pane(chat.paneID)?.terminalID, page.hasKeyboard(chat.paneID) {
                page.terminals.focus(terminalID)
            }
        }
        // The reply box takes the keyboard back.
        .onDisappear {
            if page.hasKeyboard(chat.paneID) {
                chat.wantsKeyboard = true
            }
        }
    }
}
