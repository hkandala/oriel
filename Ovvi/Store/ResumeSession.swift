import HerdrKit

extension Page {
    /// Resume (ui/window#archived): the agent's own resume line, with Ovvi's flags, in a new pane in the session's
    /// folder, shown with the keyboard: a new tab after the selected tab of the workspace whose folder holds it (else a
    /// new workspace there), or `beside` the keyboard card. A session whose folder is gone resumes nowhere, as Claude
    /// Code refuses one from another folder; but pi's, which keeps its folder in its file, in the home folder.
    func resume(_ session: ClosedSession, beside: Bool) async {
        guard let agent = Chooser.agents.first(where: { $0.command == session.agent }) else { return }
        // herdr starts a pane in the home folder when its folder is gone.
        let found = await store.machine.exec().succeeds(#"test -d "$1""#, [session.folder])
        guard found || session.agent == "pi" else {
            let folder = PathField.short(session.folder, remote: store.machine.isRemote)
            return await store.show(Notice(text: "\(folder) is gone"))
        }
        let cwd = found ? session.folder : "~", card = beside ? keyboardPane : nil
        guard let workspace = card.flatMap({ store.workspace(of: $0.tabID) }) ?? workspace(holding: cwd) else {
            if let chooser = await newWorkspace(cwd: cwd).flatMap({ store.chooser($0.id) }) {
                store.start(agent, chooser, closed: session.value)
            }
            return
        }
        await store.write { client in
            let spot = if let card {
                PanePlace.split(tab: card.tabID, pane: card.id, .right)
            } else {
                PanePlace.tab(after: selectedTabIDs[workspace.id] ?? workspace.activeTabID)
            }
            let pane = try await store.newPane(client, in: workspace.id, cwd: cwd, label: nil, spot)
            store.choose(pane, starting: agent, closed: session.value)
            follow(pane, pane.terminalID)
        }
    }

    /// The workspace whose folder holds `folder`, the deepest. A folder one or two levels deep (`/`, a home folder)
    /// holds only itself: every session is under it.
    private func workspace(holding folder: String) -> HostStore.Workspace? {
        store.workspaces.compactMap { workspace in store.root(of: workspace).map { (workspace, $0) } }
            .filter { $0.1 == folder || $0.1.split(separator: "/").count > 2 && folder.hasPrefix($0.1 + "/") }
            .max { $0.1.count < $1.1.count }?.0
    }
}
