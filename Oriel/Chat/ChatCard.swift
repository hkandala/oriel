import HerdrKit
import SwiftUI

extension Page {
    /// The pane's chat when its agent carries an adapter's launch marker (future-work/chat-view#which-panes-have-it).
    func chat(_ pane: HostStore.Pane) -> Chat? {
        guard let terminalID = pane.terminalID, let adapter = ChatAdapters.recognize(pane.program) else { return nil }
        return terminals.chat(pane, adapter, terminalID: terminalID, store: store)
    }
}

/// A chat card's header controls (future-work/chat-view#switching-views): the agent's state, the detail level while
/// the chat shows, and the chat|term switch, which changes only what the card draws.
struct ChatSwitch: View {
    @Bindable var chat: Chat
    let page: Page
    let state: AgentState?
    private var settings = AppSettings()
    @Environment(\.look) private var look

    init(chat: Chat, page: Page, state: AgentState?) {
        self.chat = chat
        self.page = page
        self.state = state
    }

    var body: some View {
        let id = chat.paneID
        HStack(spacing: 6) {
            if let (text, color) = capsule {
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(color.opacity(0.15), in: .rect(cornerRadius: 4))
                    .fixedSize()
                    .accessibilityIdentifier("pane.\(id).state")
            }
            if chat.showsChat {
                Picker("Detail", selection: settings.$chatLevel) {
                    Text("Replies").tag(ChatLevel.replies)
                    Text("Steps").tag(ChatLevel.steps)
                    Text("All").tag(ChatLevel.all)
                }
                .accessibilityIdentifier("pane.\(id).level")
            }
            Picker("View", selection: $chat.showsChat) {
                Text("Chat").tag(true)
                Text("Terminal").tag(false)
            }
            .accessibilityIdentifier("pane.\(id).view")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .onChange(of: chat.showsChat) {
            // The card keeps the keyboard: the reply box, or the terminal.
            if page.keyboardPane?.id == id, let terminalID = page.store.pane(id)?.terminalID {
                Task { page.terminals.focus(terminalID) }
            }
        }
    }

    /// Working, Needs you, Done or Error, in the status colors; none while idle.
    private var capsule: (String, Color)? {
        if chat.problem != nil {
            return ("Error", look.error)
        }
        switch chat.phase {
        case .working: return (AgentState.working.capsule, look.working)
        case .waiting: return (AgentState.needsYou.capsule, look.needsYou)
        case .ready, .starting:
            return state == .finishedUnseen ? (AgentState.finishedUnseen.capsule, look.finished) : nil
        }
    }
}
