import HerdrKit
import SwiftUI

extension Page {
    /// The pane's chat when its agent carries an adapter's launch marker (ui/chat-view#which-panes-have-it),
    /// one per pane for every window of the session.
    func chat(_ pane: HostStore.Pane) -> Chat? {
        guard let terminalID = pane.terminalID, let adapter = ChatAdapters.recognize(pane.program) else { return nil }
        if let chat = store.chats[terminalID], chat.adapter.token == adapter.token {
            // Only a change: Observation reports equal writes too, and every card body asks.
            if chat.paneID != pane.id {
                chat.paneID = pane.id
            }
            return chat
        }
        // A new launch is a new chat; the closed panes' chats go.
        let chat = Chat(adapter: adapter, paneID: pane.id, store: store)
        store.chats = store.chats.filter { id, _ in store.panes.contains { $0.terminalID == id } }
        store.chats[terminalID] = chat
        return chat
    }
}

/// A chat card's header controls (ui/chat-view#switching-views): the agent's state and the chat|term switch,
/// which changes only what the card draws.
struct ChatSwitch: View {
    @Bindable var chat: Chat
    let page: Page
    let state: AgentState?
    @Environment(\.look) private var look

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
            Segments(id: "pane.\(id).view", options: [("Chat", true), ("Terminal", false)], selection: $chat.showsChat)
        }
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

/// A small segmented control in the app's own style: a track, and the raised pill on the chosen segment, as the tab
/// bar.
struct Segments<Value: Hashable>: View {
    let id: String
    let options: [(String, Value)]
    @Binding var selection: Value
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { title, value in
                Button { selection = value } label: {
                    Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 20)
                }
                .buttonStyle(ChromeStyle(selected: selection == value, radius: 6))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(title.lowercased())")
            }
        }
        .padding(2)
        .background(look.track, in: .rect(cornerRadius: 8))
    }
}
