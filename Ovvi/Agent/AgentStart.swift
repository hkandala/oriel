import Foundation
import HerdrKit

extension AgentCommand {
    /// When each asking pane (machine, session, terminal) last notified.
    @MainActor private static var notified: [String: ContinuousClock.Instant] = [:]

    static let notify = AgentCommand(
        name: "notify", usage: "notify <title> [<body>] [--pane <pane>]",
        summary: "Posts a notification on the Mac; a click shows the pane",
        help: """
        A click shows this pane, or --pane's, and brings Ovvi to the front. One per pane every 10 s. None while the \
        user turned off Notifications ▸ From Agents ("notified": false).
        """,
    ) { call in
        let target = try call.value("--pane").map(call.target)
            ?? call.asking
        let title = try call.argument("title"), body = try call.optionalArgument() ?? ""
        try call.done()
        let (store, pane) = try call.found(target)
        guard UserDefaults.standard.bool(forKey: Notifications.fromAgents) else {
            return AgentOutput(["pane": target.id, "notified": false])
        }
        // By terminal: herdr reuses pane ids.
        let asking = call.store.pane(call.pane)?.terminalID ?? call.pane
        let now = ContinuousClock.now, from = "\(call.store.machine.id)|\(call.store.session)|\(asking)"
        notified = notified.filter { now - $0.value < .seconds(10) }
        guard notified[from] == nil else {
            throw AgentError(code: "rate_limited", message: "one notification per pane every 10 s")
        }
        notified[from] = now
        try await Notifications.post(title, body, from: call.agent, for: pane, of: store)
        return AgentOutput(["pane": target.id, "notified": true])
    }

    static let agent = AgentCommand(
        name: "agent", usage: "agent <name> [<place>]", summary: "Starts an agent with the chat view in a new pane",
        help: """
        <name>: claude, codex, pi or opencode. <place> as for open, but not --replace. It types the agent's line \
        with Ovvi's chat flags, as Start Agent Here does, and answers then, not when the agent is ready.
        """,
    ) { call in
        if call.args.contains("--replace") {
            throw AgentError.usage("--replace takes a browser or plugin card")
        }
        // The options first, so the name is the next argument; a bad name is told before a bad place.
        let place = Result { try call.place() }
        let name = try call.argument("name")
        try call.done()
        guard let agent = Chooser.agents.first(where: { $0.command == name }) else {
            throw AgentError(code: "bad_argument", message: """
            no agent \(name); there are \(Chooser.agents.map(\.command).joined(separator: ", "))
            """)
        }
        let (store, id) = try await call.newPane(place.get())
        // Its card opens on the chat, as after Relaunch with Chat.
        store.pane(id)?.relaunched = true
        let chooser = Chooser()
        chooser.paneID = id
        chooser.terminalID = store.pane(id)?.terminalID
        store.choosers.append(chooser)
        store.start(agent, chooser)
        try await store.typed(chooser, "\(agent.name) could not be typed in pane \(id)")
        return AgentOutput(["pane": id, "agent": name])
    }

    static let chat = AgentCommand(
        name: "chat", usage: "chat <pane>", summary: "Starts an idle agent again with the chat view",
        help: """
        Relaunch with Chat: the agent quits and starts again in the same session, with Ovvi's flags. It answers when \
        the line is typed, which can take over 10 s: pass --timeout 20. An agent that works or waits for the user is \
        busy; this pane is self.
        """,
    ) { call in
        let target = try call.target(call.argument("pane"))
        try call.done()
        guard target.session != call.store.session || target.id != call.pane else {
            throw AgentError(code: "self", message: "pane \(target.id) is the asking one: its agent would end first")
        }
        let (store, pane) = try call.found(target)
        let name = pane.agentLabel ?? "the agent"
        let busy = AgentError(
            code: "busy",
            message: "\(name) in pane \(target.id) is \(pane.state == .needsYou ? "waiting for you" : "working")",
        )
        guard EnableChat.offered(pane, store) else {
            if store.chooser(pane.id)?.starting != nil {
                throw AgentError(code: "busy", message: "\(name) in pane \(target.id) is starting again")
            }
            let why = ChatAdapters.adapter(pane.agent) == nil ? "runs no agent with a chat view"
                : ChatAdapters.recognize(pane.program) != nil ? "shows the chat view already"
                : "has no agent session that herdr knows"
            throw AgentError(code: "bad_argument", message: "pane \(target.id) \(why)")
        }
        guard pane.state != .working, pane.state != .needsYou else { throw busy }
        // Before it quits: herdr then lets go of the agent.
        let agent = pane.agent ?? ""
        store.enableChat(pane)
        try await store.typed(store.chooser(pane.id), "\(name) did not start again with chat")
        return AgentOutput(["pane": target.id, "agent": agent])
    }

    static let view = AgentCommand(
        name: "view", usage: "view <pane> chat|tui", summary: "Switches a chat agent's card to its chat or its TUI",
        help: "As the card's Chat | TUI switch, in every window of the session.",
    ) { call in
        let target = try call.target(call.argument("pane")), view = try call.argument("chat|tui")
        try call.done()
        guard ["chat", "tui"].contains(view) else { throw AgentError.usage("\(view) is not chat or tui") }
        let (store, pane) = try call.found(target)
        guard let chat = store.chat(pane) else {
            throw AgentError(code: "bad_argument", message: "pane \(target.id) runs no agent with a chat view")
        }
        chat.showsChat = view == "chat"
        return AgentOutput(["pane": target.id, "view": view])
    }
}

extension HostStore {
    /// Waits until the chooser typed its agent's line; one that ended first (its pane closed, the agent did not quit)
    /// fails with `failure`.
    func typed(_ chooser: Chooser?, _ failure: String) async throws {
        while let chooser, !chooser.typed, choosers.contains(where: { $0 === chooser }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard chooser?.typed == true else { throw AgentError(code: "failed", message: failure) }
    }
}
