import Foundation

/// What an agent pane shows (D14). Ordered, so a tab or a workspace shows its strongest pane.
public enum AgentState: Comparable, Sendable {
    case idle, working, finishedUnseen, needsYou
}

/// The app's own "seen" (D14, design: layout, Selection and "seen"): herdr's statuses plus which finishes the user
/// has not looked at yet, from `completion_seq`. herdr's `done` is not used. Keyed by terminal (else pane id): a moved
/// pane gets a new pane id and keeps its terminal, and herdr reuses pane ids for new terminals.
public struct Seen: Sendable {
    public struct Change: Equatable, Sendable {
        public let paneID: String
        public let state: AgentState
    }

    /// Each agent's state by key (`key(terminalID:paneID:)`).
    public private(set) var states: [String: AgentState] = [:]
    /// When each agent's state last changed, for the ages.
    public private(set) var since: [String: Date] = [:]
    private var agents: [Agent] = []
    /// Each agent's `completion_seq` recorded as seen; an agent in here was sighted (its value may be nil).
    private var seen: [String: Int?] = [:]
    /// A snapshot was applied: the first one reports no changes.
    private var started = false

    public init() {}

    public static func key(terminalID: String?, paneID: String) -> String {
        terminalID ?? paneID
    }

    /// A new snapshot's agents. `looking`: the keys of the panes the user looks at, whose finishes count as seen.
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
            let id = Self.key(terminalID: agent.terminalID, paneID: agent.paneID)
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
                    changes.append(Change(paneID: agent.paneID, state: state))
                }
            }
        }
        // An agent that went away starts over.
        seen = seen.filter { states[$0.key] != nil }
        since = since.filter { states[$0.key] != nil }
        self.states = states
        return changes
    }
}
