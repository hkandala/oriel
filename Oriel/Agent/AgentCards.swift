import HerdrKit

extension AgentCall {
    /// The asking pane as the user knows it, for a notice or a prompt: its agent's name ("Claude Code"), else the
    /// card's title.
    var agent: String {
        store.pane(pane).map { $0.agentLabel ?? $0.cardTitle } ?? pane
    }
}
