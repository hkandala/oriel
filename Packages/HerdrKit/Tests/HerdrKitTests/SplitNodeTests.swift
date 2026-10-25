@testable import HerdrKit
import Testing

private func leaf(_ id: String) -> SplitNode {
    .leaf(paneID: id)
}

private func right(_ ratio: Double, _ first: SplitNode, _ second: SplitNode) -> SplitNode {
    .split(.right, ratio: ratio, first: first, second: second)
}

private func down(_ ratio: Double, _ first: SplitNode, _ second: SplitNode) -> SplitNode {
    .split(.down, ratio: ratio, first: first, second: second)
}

/// Rounded, so 1/3 compares.
private func changes(_ list: [(path: [Bool], ratio: Double)]) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: list.map { change in
        (change.path.map { $0 ? "1" : "0" }.joined(), (change.ratio * 1000).rounded() / 1000)
    })
}

@Test func `two splits right from one pane give three thirds`() {
    // herdr halves the pane it splits: 50 / 25 / 25.
    let tree = right(0.5, leaf("p1"), right(0.5, leaf("p2"), leaf("p3")))
    #expect(changes(tree.evened(around: "p3")) == ["": 0.333])
    #expect(changes(tree.evened(around: "p1")) == ["": 0.333])
}

@Test func `a child split the other way counts as one unit and is left alone`() {
    // p1 | (p2 / p4) | p3, with the down split at 0.7.
    let tree = right(0.5, leaf("p1"), right(0.5, down(0.7, leaf("p2"), leaf("p4")), leaf("p3")))
    #expect(changes(tree.evened(around: "p3")) == ["": 0.333])
    // p4's run is the down split alone.
    #expect(changes(tree.evened(around: "p4")) == ["10": 0.5])
    #expect(changes(tree.evened()) == ["": 0.333, "10": 0.5])
}

@Test func `a run spans both sides of its top split`() {
    // (p1 | p2) | (p3 | p4) after splitting p1: four quarters.
    let tree = right(0.5, right(0.5, leaf("p1"), leaf("p2")), right(0.3, leaf("p3"), leaf("p4")))
    #expect(changes(tree.evened(around: "p2")) == ["1": 0.5])
    let uneven = right(0.6, right(0.5, leaf("p1"), leaf("p5")), right(0.5, leaf("p3"), leaf("p4")))
    #expect(changes(uneven.evened(around: "p5")) == ["": 0.5])
}

@Test func `an even run or a lone pane needs no change`() {
    #expect(leaf("p1").evened(around: "p1").isEmpty)
    #expect(right(0.5, leaf("p1"), leaf("p2")).evened(around: "p2").isEmpty)
    #expect(right(0.5, leaf("p1"), leaf("p2")).evened(around: "gone").isEmpty)
    #expect(right(0.5, leaf("p1"), down(0.5, leaf("p2"), leaf("p3"))).paneIDs == ["p1", "p2", "p3"])
}

@Test func `a removed pane gives its place to its sibling`() {
    let tree = right(0.6, leaf("p1"), down(0.5, leaf("p2"), leaf("p3")))
    #expect(tree.removing(["p2"]) == right(0.6, leaf("p1"), leaf("p3")))
    #expect(tree.removing(["p1"]) == down(0.5, leaf("p2"), leaf("p3")))
    #expect(tree.removing(["p2", "p3"]) == leaf("p1"))
    #expect(tree.removing(["p1", "p2", "p3"]) == nil)
    #expect(tree.removing([]) == tree)
}
