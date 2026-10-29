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
        // A new launch is a new chat (a closed pane's goes with the snapshot that drops it).
        let chat = Chat(adapter: adapter, paneID: pane.id, store: store)
        chat.showsChat = pane.relaunched
        pane.relaunched = false
        store.chats[terminalID] = chat
        return chat
    }

    /// The chat a pane's card shows in place of its terminal: not under a chooser, not floated, its switch on Chat.
    func shownChat(_ pane: HostStore.Pane) -> Chat? {
        guard store.chooser(pane.id) == nil, !floats(pane), let chat = chat(pane), chat.showsChat else { return nil }
        return chat
    }

    /// The pane's card has the window's keyboard, or the pane floats: its window has its own.
    func hasKeyboard(_ paneID: String) -> Bool {
        keyboardPane?.id == paneID || store.pane(paneID).map(floats) == true
    }
}

/// A chat card's row-2 controls (ui/chat-view#switching-views): the detail level while the chat shows, and the
/// Chat | TUI switch, which changes only what the card draws.
struct ChatSwitch: View {
    @Bindable var chat: Chat
    let page: Page
    private var settings = AppSettings()

    var body: some View {
        let id = chat.paneID
        HStack(spacing: 8) {
            if chat.showsChat {
                level
            }
            Segments(id: "pane.\(id).view", options: [("Chat", true), ("TUI", false)], selection: $chat.showsChat)
        }
        .fixedSize()
        .onChange(of: chat.showsChat) {
            // The card keeps the keyboard: the reply box, or the terminal; in a floating window too.
            guard page.hasKeyboard(id), let terminalID = page.store.pane(id)?.terminalID else { return }
            Task { page.terminals.focus(terminalID) }
        }
    }

    /// "Show: Replies ⌄", a pull-down of the levels (ui/chat-view#detail-levels).
    private var level: some View {
        Menu {
            Picker("Show", selection: settings.$chatLevel) {
                ForEach(ChatLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // One text: an image beside it was a second element with the menu's identifier.
            let chevron = Text(Image(systemName: "chevron.down")).font(.system(size: 8, weight: .semibold))
            Text("Show: \(settings.chatLevel.title)  \(chevron)")
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 24)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 6))
        .fixedSize()
        .accessibilityLabel("Show")
        .accessibilityValue(settings.chatLevel.title)
        .accessibilityIdentifier("chat.\(chat.paneID).level")
    }
}

extension ChatLevel {
    var title: String {
        rawValue.capitalized
    }
}

/// A chat card's state capsule; none while idle.
struct ChatCapsule: View {
    let chat: Chat
    let state: AgentState?
    @Environment(\.look) private var look

    var body: some View {
        if let (text, color) = capsule {
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(color.opacity(0.15), in: .rect(cornerRadius: 4))
                .fixedSize()
                .accessibilityIdentifier("pane.\(chat.paneID).state")
        }
    }

    private var capsule: (String, Color)? {
        // Only while the chat shows: nothing follows the agent behind its terminal, so nothing would clear it.
        if chat.problem != nil, chat.showsChat {
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

/// A small segmented control in the app's own style, as the tab bar.
struct Segments: View {
    let id: String
    let options: [(String, Bool)]
    @Binding var selection: Bool
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
