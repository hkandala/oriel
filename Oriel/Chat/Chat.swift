import Foundation
import HerdrKit
import Observation

/// An agent pane's chat (ui/chat-view): the agent's history, whether it is ready, working or waiting, the
/// messages on their way, and whether the card shows the chat or the terminal. The session's store keeps it by
/// terminal id, for every window; its adapter follows the agent while a card shows the chat.
@MainActor @Observable
final class Chat {
    enum Phase: Equatable {
        case starting, ready, working, waiting
    }

    /// A message sent with `agent.prompt`, shown until the history has it.
    struct Outgoing: Identifiable, Equatable {
        let id = UUID()
        let text: String
        var notSent = false
    }

    let adapter: any ChatAdapter
    var paneID: String
    @ObservationIgnored weak var store: HostStore?
    var history = ChatHistory() {
        didSet { confirm() }
    }

    /// The card shows the chat; else its terminal (kept in memory per pane).
    var showsChat = true
    /// The phase the agent itself records (a session record, a state file, its server); nil without one: herdr's
    /// status then.
    var recorded: Phase?
    /// What the agent asks that the chat can answer, shown while it waits.
    var question: ChatQuestion?
    /// Why the chat cannot read the session; Show Terminal then.
    var problem: String?
    var outgoing: [Outgoing] = []
    /// The reply box's text, shared by every card of the pane.
    var draft = ""
    /// The reply box takes the keyboard when it shows, or now (the card got the keyboard).
    var wantsKeyboard = false
    /// Where each followed file was read up to, so a card shown again goes on from there.
    @ObservationIgnored var marks: [String: FileMark] = [:]
    /// The history's file, from the agent's side file.
    @ObservationIgnored var source: String?
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var following: Task<Void, Never>?

    init(adapter: any ChatAdapter, paneID: String, store: HostStore) {
        self.adapter = adapter
        self.paneID = paneID
        self.store = store
    }

    /// The agent's own record, else herdr's status (ui/chat-view#ready-working-waiting).
    var phase: Phase {
        if let recorded {
            return recorded
        }
        switch store?.pane(paneID)?.state {
        case .needsYou: return .waiting
        case .working: return .working
        case .idle, .finishedUnseen: return .ready
        case nil: return .starting
        }
    }

    /// The model of the last reply and its thinking effort, as the agent's files say; nil when they don't.
    var model: String? {
        history.model
    }

    var effort: String? {
        history.effort
    }

    /// Its pane still runs this launch of the agent.
    var live: Bool {
        ChatAdapters.recognize(store?.pane(paneID)?.program)?.token == adapter.token
    }

    /// Waiting on something the chat cannot answer: the live terminal takes the bottom of the card.
    var drawer: Bool {
        phase == .waiting && question == nil
    }

    /// While a card shows the chat, the adapter follows the agent; the last card to go stops it.
    func viewed() async {
        viewers += 1
        if viewers == 1, let store {
            let old = following
            following = Task {
                // A card gone and back at once: the last follow ends first, so two never read from one mark.
                await old?.value
                let exec = await store.machine.exec()
                // Again after a lost connection, from the marks.
                while !Task.isCancelled {
                    await adapter.follow(self, on: exec)
                    try? await Task.sleep(for: .seconds(2))
                }
                // Not followed, it would go stale: herdr's status until a card shows the chat again. Once the adapter
                // returned, so no task of its writes after.
                if viewers == 0 {
                    recorded = nil
                }
            }
        }
        defer {
            viewers -= 1
            if viewers == 0 {
                following?.cancel()
            }
        }
        // Until the card goes.
        while await (try? Task.sleep(for: .seconds(3600))) != nil {}
    }

    /// Sends the text when the agent can take it (ready, or working: it queues it); text that starts with `/` is typed
    /// into the terminal instead, which the card shows.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client = store?.client else { return }
        if text.hasPrefix("/") {
            showsChat = false
            draft = ""
            Task { try? await client.sendInput(text, keys: [], pane: paneID) }
            return
        }
        guard phase == .ready || phase == .working else { return }
        let message = Outgoing(text: text)
        outgoing.removeAll(where: \.notSent)
        outgoing.append(message)
        draft = ""
        Task {
            let sent = await (try? client.prompt(text, pane: paneID)) != nil
            if !sent {
                notSent(message.id)
                return
            }
            // Sent means the history has it (Claude Code's company hooks can take a few seconds). pi steers: a message
            // sent while it works shows in its history when it takes it, after the running tool (or its dialog).
            try? await Task.sleep(for: .seconds(5))
            while phase == .working || phase == .waiting {
                try? await Task.sleep(for: .seconds(1))
            }
            notSent(message.id)
        }
    }

    /// The draft comes back unless the user typed another.
    private func notSent(_ id: UUID) {
        guard let index = outgoing.firstIndex(where: { $0.id == id && !$0.notSent }) else { return }
        outgoing[index].notSent = true
        if draft.isEmpty {
            draft = outgoing[index].text
        }
    }

    /// The oldest message on its way that the history now has, by its text.
    private func confirm() {
        guard !outgoing.isEmpty, case let .user(text)? = history.entries.last?.kind else { return }
        let sent = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = outgoing.firstIndex(where: { $0.text == sent }),
           // Confirmed after "Not sent": the draft it gave back would send it twice.
           outgoing.remove(at: index).notSent, draft == sent
        {
            draft = ""
        }
    }

    /// The agent's interrupt, only while it works.
    func stop() {
        guard phase == .working, let client = store?.client else { return }
        let keys = type(of: adapter).stopKeys, paneID = paneID
        Task { try? await client.sendKeys(keys, pane: paneID) }
    }

    /// An answer that did not reach the agent (its hook gone, the server or the connection failed) drops the card:
    /// the live terminal takes it.
    func answer(_ answers: [String: String]) {
        guard let question, !question.answered, let store else { return }
        self.question?.answered = true
        Task {
            if await !adapter.answer(question, answers, on: store.machine.exec()), self.question?.raw == question.raw {
                self.question = nil
            }
        }
    }
}

/// A question the chat can answer (ui/chat-view#waiting): its questions and their options, and what the adapter needs
/// to answer it (the questions as the agent sent them, a request's id).
struct ChatQuestion: Equatable {
    struct Item: Equatable {
        let text: String
        let options: [String]
    }

    let items: [Item]
    let raw: Data
    /// Answered in the chat: it stays, disabled, until the agent goes on (no drawer meanwhile).
    var answered = false
}

extension ChatQuestion {
    /// Questions as Claude Code and OpenCode send them (`question`, `options[].label`); nil when one takes several
    /// answers (`several` is the agent's key for it) or has no options: the live terminal answers those.
    static func items(_ questions: [[String: Any]], several: String) -> [Item]? {
        let items = questions.map { question in
            Item(text: question["question"] as? String ?? "",
                 options: (question["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String })
        }
        guard !items.isEmpty, !questions.contains(where: { $0[several] as? Bool == true }),
              items.allSatisfy({ !$0.options.isEmpty }) else { return nil }
        return items
    }
}
