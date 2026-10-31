import HerdrKit
import SwiftUI

/// An agent card's chat (ui/chat-view#what-it-looks-like).
struct ChatView: View {
    @Bindable var chat: Chat
    let page: Page
    let terminal: PaneTerminal?
    /// The conversation's reading column, as in Messages: a wide card centers it.
    static let column: CGFloat = 760
    @State private var height: CGFloat = 0
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatMessages(chat: chat, page: page, composing: $composing).equatable()
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
}

/// The reply box (ui/chat-view#what-it-looks-like): its own view, so a key typed in it changes nothing else.
struct Composer: View {
    @Bindable var chat: Chat
    var composing: FocusState<Bool>.Binding
    /// Its text from its sides.
    static let inset: CGFloat = 18

    var body: some View {
        let working = chat.phase == .working
        return VStack(alignment: .leading, spacing: 2) {
            TextField("Ask Anything", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1 ... 5)
                .focused(composing)
                .onSubmit { chat.send(chat.draft) }
                // ⇧Return adds a line, as ⌥Return does.
                .onKeyPress(.return, phases: [.down, .repeat]) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                    return .handled
                }
                // Its text ends as far in as it starts; Send sits closer to the box's side.
                .padding(.trailing, Self.inset - 11)
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
                    // Always in the accent; `send` does nothing with an empty box or while the agent cannot take it.
                    roundButton("arrow.up", help: "Send", id: "chat.\(chat.paneID).send") { chat.send(chat.draft) }
                }
            }
        }
        .padding(.leading, Self.inset).padding(.trailing, 11).padding(.top, 13).padding(.bottom, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture { composing.wrappedValue = true }
    }

    private func roundButton(_ symbol: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Look.onAccent)
                .frame(width: 22, height: 22)
                .background(.tint, in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
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
                Button("Open TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
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
