import HerdrKit

extension HostStore {
    /// Relaunch with Chat (ui/chat-view#which-panes-have-it): an agent herdr knows, started without Ovvi's flags, in a
    /// session herdr knows, again with the flags in that session, with the chooser's loader meanwhile.
    func enableChat(_ pane: Pane) {
        guard let agent = Chooser.agents.first(where: { $0.command == pane.agent }), let session = pane.session,
              chooser(pane.id) == nil else { return }
        let chooser = Chooser()
        chooser.paneID = pane.id
        chooser.terminalID = pane.terminalID
        choosers.append(chooser)
        pane.relaunched = true
        start(agent, chooser, resume: session)
    }

    /// The agent's line with Ovvi's flags (Relaunch with Chat's, made before its agent quit), else its command.
    func firstLine(_ agent: Chooser.Agent, _ resumed: String?) async -> String {
        if let resumed {
            return resumed
        }
        return await ChatAdapters.launch(agent.command, on: machine.exec()) ?? agent.command
    }

    /// Relaunch with Chat's launch line, made first so a failed run on the machine leaves the agent running, once the
    /// agent quit; nil (with a notice) when either failed, and with no session.
    func restart(_ agent: Chooser.Agent, _ chooser: Chooser, _ session: String?) async -> String? {
        guard let session else { return nil }
        guard let id = chooser.paneID,
              let line = await ChatAdapters.launch(agent.command, resume: session, on: machine.exec())
        else {
            await show(Notice(text: "\(agent.name) could not start with chat"))
            return nil
        }
        guard await quit(id, agent, chooser) else {
            // A closed pane's chooser is gone: nothing to say.
            if choosers.contains(where: { $0 === chooser }) {
                await show(Notice(text: "\(agent.name) did not quit"))
            }
            return nil
        }
        return line
    }

    /// Quits the agent as its user would: a turn or a dialog stopped first, the prompt cleared (⌃C, which alone ends
    /// OpenCode with an empty prompt), then its quit command. True once only the shell runs and herdr let go of the
    /// agent, within 10 s, while its chooser is there (its pane did not close).
    private func quit(_ paneID: String, _ agent: Chooser.Agent, _ chooser: Chooser) async -> Bool {
        guard let client, let adapter = ChatAdapters.adapter(agent.command) else { return false }
        if pane(paneID)?.state.map({ $0 == .working || $0 == .needsYou }) == true {
            try? await client.sendKeys(adapter.stopKeys, pane: paneID)
            try? await Task.sleep(for: .seconds(1))
        }
        try? await client.sendKeys(["ctrl+c"], pane: paneID)
        var typed = false
        let clock = ContinuousClock(), begun = clock.now
        while clock.now - begun < .seconds(10), choosers.contains(where: { $0 === chooser }) {
            // OpenCode stops its server first: the quit command would land in the shell.
            try? await Task.sleep(for: .seconds(typed ? 0.3 : 2))
            guard await (try? client.program(paneID))?.isShell == true else {
                if !typed {
                    typed = true
                    try? await client.sendInput(adapter.quit, keys: ["enter"], pane: paneID)
                }
                continue
            }
            if await (try? client.pane(paneID))?.agent == nil {
                return true
            }
        }
        return false
    }
}
