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
    @Environment(\.look) private var look

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

    /// "Replies only ⌄", a pull-down of the levels in a pill like Chat | TUI's (ui/chat-view#detail-levels).
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
            Text("\(settings.chatLevel.title)  \(chevron)")
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 20)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 6))
        .fixedSize()
        .padding(2)
        .background(look.track, in: .rect(cornerRadius: 8))
        .accessibilityLabel("Show")
        .accessibilityValue(settings.chatLevel.title)
        .accessibilityIdentifier("chat.\(chat.paneID).level")
    }
}

extension ChatLevel {
    var title: String {
        self == .replies ? "Replies only" : rawValue.capitalized
    }
}

/// An agent card's state as t3code draws a thread's: a dot and the word, in the state's color. A chat's follows its
/// phase and shows none while idle; another agent's is herdr's.
struct CardState: View {
    let chat: Chat?
    let state: AgentState?
    let paneID: String
    @Environment(\.look) private var look

    var body: some View {
        if let (text, color) = label {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityValue(text)
            .accessibilityIdentifier("pane.\(paneID).state")
        }
    }

    private var label: (String, Color)? {
        guard let chat else { return state.map { ($0.capsule, $0.color(look)) } }
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
