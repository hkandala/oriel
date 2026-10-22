import Foundation
@testable import HerdrKit
import Testing

private func agent(_ status: AgentStatus, _ completion: Int? = nil, pane: String = "w1:p1") -> Agent {
    Agent(paneID: pane, terminalID: nil, agent: "codex", displayAgent: nil, status: status, completionSeq: completion)
}

@Test func `the first sighting counts as seen and reports nothing`() {
    var seen = Seen()
    let changes = seen.update([agent(.idle, 4), agent(.blocked, pane: "w1:p2")], looking: [])
    #expect(changes.isEmpty)
    #expect(seen.states == ["w1:p1": .idle, "w1:p2": .needsYou])
    // An agent that shows up later is a first sighting too, but reported.
    let later = seen.update([agent(.idle, 4), agent(.blocked, pane: "w1:p2"), agent(.idle, 9, pane: "w1:p3")],
                            looking: [])
    #expect(later.map(\.state) == [.idle])
    #expect(seen.states["w1:p3"] == .idle)
}

@Test func `a finish is unseen until the user looks at the pane`() {
    var seen = Seen()
    _ = seen.update([agent(.idle, 2)], looking: [])
    let start = Date(timeIntervalSince1970: 100)
    #expect(seen.update([agent(.working)], looking: [], now: start).map(\.state) == [.working])
    #expect(seen.since["w1:p1"] == start)
    #expect(seen.update([agent(.idle, 5)], looking: []).map(\.state) == [.finishedUnseen])
    // Another snapshot with the same finish changes nothing.
    #expect(seen.update([agent(.idle, 5)], looking: ["w1:p2"]).isEmpty)
    #expect(seen.look(["w1:p1"]).map(\.state) == [.idle])
    #expect(seen.states["w1:p1"] == .idle)
}

@Test func `a finish while the user looks is seen at once`() {
    var seen = Seen()
    _ = seen.update([agent(.working)], looking: ["w1:p1"])
    #expect(seen.update([agent(.idle, 3)], looking: ["w1:p1"]).map(\.state) == [.idle])
    #expect(seen.update([agent(.idle, 3)], looking: []).isEmpty)
}

@Test func `blocked needs you and its end is a finish`() {
    var seen = Seen()
    _ = seen.update([agent(.idle)], looking: [])
    #expect(seen.update([agent(.blocked)], looking: []).map(\.state) == [.needsYou])
    // Looking does not answer it.
    #expect(seen.look(["w1:p1"]).isEmpty)
    #expect(seen.update([agent(.idle, 7)], looking: []).map(\.state) == [.finishedUnseen])
    // herdr's done is not used: the counter decides.
    #expect(seen.update([agent(.done, 7)], looking: []).isEmpty)
}

@Test func `a restart of herdr counts its new finishes`() {
    var seen = Seen()
    _ = seen.update([agent(.idle, 8)], looking: [])
    #expect(seen.states["w1:p1"] == .idle)
    // The counter starts at 0 again: a smaller number is still a new finish.
    _ = seen.update([agent(.working)], looking: [])
    #expect(seen.update([agent(.idle, 2)], looking: []).map(\.state) == [.finishedUnseen])
}

@Test func `a reconnect reports changes against the last known state`() {
    var seen = Seen()
    _ = seen.update([agent(.working), agent(.idle, 1, pane: "w1:p2")], looking: [])
    // The stream dropped; meanwhile p1 finished, p2 went away and came back blocked.
    let changes = seen.update([agent(.idle, 6), agent(.blocked, pane: "w1:p2")], looking: [])
    #expect(changes.map(\.paneID) == ["w1:p1", "w1:p2"])
    #expect(changes.map(\.state) == [.finishedUnseen, .needsYou])
}

@Test func `a pane that loses its agent starts over`() {
    var seen = Seen()
    _ = seen.update([agent(.idle, 3)], looking: [])
    _ = seen.update([], looking: [])
    #expect(seen.states.isEmpty)
    #expect(seen.since.isEmpty)
    // Back with an old finish: a first sighting again.
    _ = seen.update([agent(.idle, 5)], looking: [])
    #expect(seen.states["w1:p1"] == .idle)
}
