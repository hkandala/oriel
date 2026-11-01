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
        case .tab: (near, split) = (PaneTarget(session: store.session, id: pane, machine: store.machine), nil)
        case .replace: throw AgentError.usage("--replace makes no pane")
        }
        guard let store = near.store else {
            throw AgentError(code: "failed", message: "Oriel does not show herdr session \(near.session)")
        }
        guard let card = store.pane(near.id), let workspace = store.workspace(of: card.tabID),
              let index = workspace.tabs.firstIndex(where: { $0.id == card.tabID })
        else { throw AgentError(
            code: "pane_not_found",
            message: "pane \(near.id) is not in herdr session \(near.session)",
        ) }
        let made = try await store.request { client in
            try await store.newPane(client, in: workspace.id, cwd: cwd, label: label,
                                    split.map { .split(tab: card.tabID, pane: card.id, $0) } ?? .tab(after: index))
        }
        let end = ContinuousClock.now + .seconds(5)
        while store.pane(made.id) == nil, end > .now {
            try await Task.sleep(for: .milliseconds(50))
        }
        if case .tab(float: true) = place {
            var float = AgentCall(store: store, pane: pane, cwd: cwd, id: id, args: [made.id])
            _ = try await AgentCommand.float.run(&float)
        }
        return (store, made.id)
    }
}

extension HostStore {
    /// One write for a request, after the writes before it, as `write` does: its error goes back to the command, not to
    /// a notice.
    func request<T>(_ action: (any Multiplexer) async throws -> T) async throws -> T {
        guard let client else {
            throw AgentError(code: "failed", message: "Oriel is not connected to herdr session \(session)")
        }
        await writes.enter()
        let result: Result<T, Error>
        do {
            result = try await .success(action(client))
        } catch {
            result = .failure(error)
        }
        writes.leave()
        await client.refresh()
        return try result.get()
    }
}
