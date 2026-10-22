import Foundation

/// What an agent pane shows (D14). Ordered, so a tab or a workspace shows its strongest pane.
public enum AgentState: Comparable, Sendable {
    case idle, working, finishedUnseen, needsYou
}

/// The app's own "seen" (D14, design: layout, Selection and "seen"): herdr's statuses plus which finishes the user
/// has not looked at yet, from `completion_seq`. herdr's `done` is not used.
public struct Seen: Sendable {
    /// A pane's state changed.
    public struct Change: Equatable, Sendable {
        public let paneID: String
        public let state: AgentState
    }

    /// Each agent pane's state.
    public private(set) var states: [String: AgentState] = [:]
    /// When each pane's state last changed, for the ages.
    public private(set) var since: [String: Date] = [:]
    private var agents: [Agent] = []
    /// Each pane's `completion_seq` recorded as seen; a pane in here was sighted (its value may be nil).
    private var seen: [String: Int?] = [:]
    /// A snapshot was applied: the first one reports no changes.
    private var started = false

    public init() {}

    /// A new snapshot's agents. `looking`: the panes the user looks at, whose finishes count as seen.
    public mutating func update(_ agents: [Agent], looking: Set<String>, now: Date = .now) -> [Change] {
        self.agents = agents
        defer { started = true }
        return look(looking, now: now)
    }

    /// The user looks at other panes (the same snapshot).
    @discardableResult
    public mutating func look(_ looking: Set<String>, now: Date = .now) -> [Change] {
        var states: [String: AgentState] = [:]
        var changes: [Change] = []
        for agent in agents {
            let id = agent.paneID
            // The first sighting counts as seen: no flood of old finishes after launch.
            if seen[id] == nil || looking.contains(id) {
                seen[id] = .some(agent.completionSeq)
            }
            // Different, not greater: the counter starts at 0 again when herdr restarts.
            let finished = agent.completionSeq != nil && agent.completionSeq != seen[id] ?? nil
            let state: AgentState = switch agent.status {
            case .blocked: .needsYou
            case .working: .working
            default: finished ? .finishedUnseen : .idle
            }
            states[id] = state
            if self.states[id] != state {
                since[id] = now
                if started {
                    changes.append(Change(paneID: id, state: state))
                }
            }
        }
        // A pane that lost its agent starts over.
        seen = seen.filter { states[$0.key] != nil }
        since = since.filter { states[$0.key] != nil }
        self.states = states
        return changes
    }
}
