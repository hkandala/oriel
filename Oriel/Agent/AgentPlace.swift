import HerdrKit

/// Where `open` and `agent` put a new pane (agent-control/cli, open's `<place>`). It never selects a tab or moves the
/// keyboard: the user's view stays where it is.
enum AgentPlace {
    /// A split of the pane, to its right or below; the asking pane's by default.
    case beside(PaneTarget, down: Bool)
    /// A new tab right after the asking pane's tab, not selected; with `float`, its pane floats then.
    case tab(float: Bool)
    /// That browser or plugin card shows something else (`open` only).
    case replace(PaneTarget)
}

extension AgentCall {
    /// Reads the place's options, at most one of `--beside <pane> [--down]`, `--down`, `--tab`, `--float` and
    /// `--replace <pane>`.
    mutating func place() throws -> AgentPlace {
        let down = flag("--down"), tab = flag("--tab"), float = flag("--float")
        let beside = try value("--beside"), replace = try value("--replace")
        guard [beside != nil || down, tab, float, replace != nil].count(where: \.self) <= 1 else {
            throw AgentError.usage("give one place: --beside <pane> [--down], --tab, --float or --replace <pane>")
        }
        if let replace {
            return try .replace(target(replace))
        }
        return tab || float ? .tab(float: float) : try .beside(target(beside ?? pane), down: down)
    }

    /// A new pane at the place (not `replace`), in the session of the pane it goes beside, made in the request's
    /// folder: a card with its label and placeholder (plugins/labels#create), else a shell. Its session's store and
    /// the pane's id, once a snapshot has it; a `float` place floats it as `oriel float` does.
    func newPane(_ place: AgentPlace, label: PaneLabel? = nil) async throws -> (store: HostStore, pane: String) {
        let near: PaneTarget, split: SplitNode.Direction?
        switch place {
        case let .beside(target, down): (near, split) = (target, down ? .down : .right)
        case .tab: (near, split) = (asking, nil)
        case .replace: throw AgentError.usage("--replace makes no pane")
        }
        let found = try found(near), store = found.0
        if case .tab(float: true) = place, store.windows.isEmpty {
            throw AgentError.noWindow(store.session)
        }
        let made = try await store.request { client in
            // Its tab and index once the writes before it are done: they can move tabs.
            guard let card = store.pane(found.1.id), let workspace = store.workspace(of: card.tabID),
                  let index = workspace.tabs.firstIndex(where: { $0.id == card.tabID })
            else { throw AgentError(code: "pane_not_found", message: "pane \(near.id) is in no tab") }
            let spot = split.map { PanePlace.split(tab: card.tabID, pane: card.id, $0) } ?? .tab(after: index)
            return try await store.newPane(client, in: workspace.id, cwd: cwd, label: label, spot)
        }
        // In its place: a snapshot between the new tab and the move has it in the temporary tab.
        try await settle { store.pane(made.id)?.tabID == made.tabID }
        if case .tab(float: true) = place {
            var float = AgentCall(store: store, pane: pane, cwd: cwd, id: id, args: [made.id])
            do {
                _ = try await AgentCommand.float.run(&float)
            } catch {
                // Not left behind with no name in the answer.
                try? await store.request { try await $0.close(pane: made.id) }
                throw error
            }
        }
        return (store, made.id)
    }
}

/// Waits up to `limit` for what the snapshots show, 50 ms between looks.
func settle(for limit: Duration = .seconds(5), _ done: () -> Bool) async throws {
    let end = ContinuousClock.now + limit
    while !done(), end > .now {
        try await Task.sleep(for: .milliseconds(50))
    }
}
