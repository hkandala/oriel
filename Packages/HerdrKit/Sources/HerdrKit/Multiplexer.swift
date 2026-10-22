/// One session of a terminal multiplexer, as the app uses it (design D49): the app talks to this, never to
/// herdr's methods or argv. `HerdrClient` is the only implementation. It grows a requirement when the app uses
/// a new feature, not before.
public protocol Multiplexer: Sendable {
    /// Every session on this machine, running or not.
    func sessions() async throws -> [Session]
    /// The whole layout now, with every tab's split tree.
    func snapshot() async throws -> Snapshot
    /// Snapshots as the session changes, paced, until the stream is dropped. Called once.
    func updates() async -> AsyncStream<Update>
    /// Reads a snapshot now, or once more after the read in flight (after the app's own write).
    func refresh() async
    #if os(macOS)
        /// Starts this session's server and waits until it answers; false when it already ran.
        @discardableResult
        func startServer() async throws -> Bool
    #endif

    /// One pane now: its cwd follows a `cd` that no event reports.
    func pane(_ paneID: String) async throws -> Pane
    /// What the pane runs besides its shell, else the shell (`isShell`, design D41).
    func program(_ paneID: String) async throws -> Program?
    /// A pane's terminal by its terminal id: control it, or only watch it.
    func terminal(_ terminalID: String, cols: Int, rows: Int, observe: Bool, takeover: Bool) async throws
        -> TerminalStream

    /// Actions. None moves the multiplexer's focus.
    func split(_ paneID: String, _ direction: SplitNode.Direction) async throws
    /// Returns the new tab's id.
    func newTab(workspace workspaceID: String, cwd: String) async throws -> String?
    /// Returns the new workspace's first tab. Without a label the multiplexer names it.
    func newWorkspace(label: String?, cwd: String) async throws -> Tab?
    func rename(workspace workspaceID: String, label: String) async throws
    /// Moves the workspaces, in this order, before another one, or last.
    func move(workspaces workspaceIDs: [String], before workspaceID: String?) async throws
    /// `group` also closes the workspace's linked worktree workspaces; herdr refuses to close a repository's
    /// workspace that has them without it.
    func close(workspace workspaceID: String, group: Bool) async throws
    func close(pane paneID: String) async throws
    func close(tab tabID: String) async throws
    func rename(tab tabID: String, label: String) async throws
    /// Moves the tab before the tab now at `index` in its workspace (the count puts it last).
    func move(tab tabID: String, to index: Int) async throws
    /// Logical keys (`ctrl+c`), encoded by the multiplexer for the program's input modes.
    func sendKeys(_ keys: [String], pane paneID: String) async throws
}

extension HerdrClient: Multiplexer {
    public nonisolated func split(_ paneID: String, _ direction: SplitNode.Direction) async throws {
        let _: Created = try await call("pane.split", ["target_pane_id": paneID, "direction": direction.rawValue,
                                                       "focus": false])
    }

    public nonisolated func newTab(workspace workspaceID: String, cwd: String) async throws -> String? {
        try await (call("tab.create", ["workspace_id": workspaceID, "cwd": cwd, "focus": false]) as Created).tab?.id
    }

    public nonisolated func newWorkspace(label: String?, cwd: String) async throws -> Tab? {
        var params: [String: any Sendable] = ["cwd": cwd, "focus": false]
        params["label"] = label
        return try await (call("workspace.create", params) as Created).tab
    }

    public nonisolated func rename(workspace workspaceID: String, label: String) async throws {
        let _: Created = try await call("workspace.rename", ["workspace_id": workspaceID, "label": label])
    }

    public nonisolated func move(workspaces workspaceIDs: [String], before workspaceID: String?) async throws {
        var params: [String: any Sendable] = ["workspace_ids": workspaceIDs]
        params["before_workspace_id"] = workspaceID
        let _: Created = try await call("workspace.move_block", params)
    }

    public nonisolated func close(workspace workspaceID: String, group: Bool) async throws {
        let _: Created = try await call("workspace.close", ["workspace_id": workspaceID, "close_group": group])
    }

    public nonisolated func close(pane paneID: String) async throws {
        let _: Created = try await call("pane.close", ["pane_id": paneID])
    }

    public nonisolated func close(tab tabID: String) async throws {
        let _: Created = try await call("tab.close", ["tab_id": tabID])
    }

    public nonisolated func rename(tab tabID: String, label: String) async throws {
        let _: Created = try await call("tab.rename", ["tab_id": tabID, "label": label])
    }

    public nonisolated func move(tab tabID: String, to index: Int) async throws {
        let _: Created = try await call("tab.move", ["tab_id": tabID, "insert_index": index])
    }

    public nonisolated func sendKeys(_ keys: [String], pane paneID: String) async throws {
        let _: Created = try await call("pane.send_keys", ["pane_id": paneID, "keys": keys])
    }
}
