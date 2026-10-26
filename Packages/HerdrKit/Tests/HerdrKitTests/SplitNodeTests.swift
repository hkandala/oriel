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

@Test func `a split is drawn as herdr makes it, evened`() {
    #expect(leaf("p1").split("p1", .right, new: "n", before: false) == right(0.5, leaf("p1"), leaf("n")))
    #expect(leaf("p1").split("p1", .down, new: "n", before: true) == down(0.5, leaf("n"), leaf("p1")))
    // p1 | p2, p2 split right: three thirds.
    let thirds = right(0.5, leaf("p1"), leaf("p2")).split("p2", .right, new: "n", before: false)
    #expect(thirds.paneIDs == ["p1", "p2", "n"])
    #expect(changes(thirds.evened()).isEmpty)
    guard case let .split(_, ratio, _, _) = thirds else { return }
    #expect((ratio * 1000).rounded() == 333)
    // The other way: a new run of its own.
    #expect(right(0.6, leaf("p1"), leaf("p2")).split("p1", .down, new: "n", before: false)
        == right(0.6, down(0.5, leaf("p1"), leaf("n")), leaf("p2")))
}

@Test func `the rebuild moves give the tree back from its first pane`() {
    // (p1 / (p3 | p4)) | p2, as herdr would split p1 for each move.
    let tree = right(0.3, down(0.6, leaf("p1"), right(0.4, leaf("p3"), leaf("p4"))), leaf("p2"))
    func placing(_ node: SplitNode, _ step: SplitNode.Move) -> SplitNode {
        switch node {
        case let .leaf(id):
            id == step.beside ? .split(step.direction, ratio: step.ratio, first: node, second: leaf(step.paneID)) : node
        case let .split(direction, ratio, first, second):
            .split(direction, ratio: ratio, first: placing(first, step), second: placing(second, step))
        }
    }
    #expect(tree.rebuild.map(\.paneID) == ["p2", "p3", "p4"])
    #expect(tree.rebuild.reduce(leaf("p1"), placing) == tree)
    #expect(leaf("p1").rebuild.isEmpty)
}

@Test func `the neighbor that way is the one used last, else the one sharing most of the edge, else the top one`() {
    // The user's layout (phase 29): three columns, the third in four rows.
    // Even rows as herdr gives them back: its ratios are 32-bit floats.
    let rows = down(0.25, leaf("r1"), down(Double(Float(1.0 / 3)), leaf("r2"), down(0.5, leaf("r3"), leaf("r4"))))
    let tree = right(1 / 3, leaf("a"), right(0.5, leaf("b"), rows))
    #expect(tree.neighbor(of: "a", .right) == "b")
    // Four rows share the edge equally: the top one (herdr's `pane.neighbor` gave the second).
    #expect(tree.neighbor(of: "b", .right) == "r1")
    #expect(tree.neighbor(of: "b", .right, used: ["r3", "a"]) == "r3")
    #expect(tree.neighbor(of: "r3", .left) == "b")
    #expect(tree.neighbor(of: "r3", .up) == "r2")
    #expect(tree.neighbor(of: "r4", .down) == nil)
    #expect(tree.neighbor(of: "a", .left) == nil)
    // The one sharing most: the first column's top pane covers most of the second's edge.
    let uneven = right(0.5, down(0.7, leaf("t"), leaf("u")), leaf("v"))
    #expect(uneven.neighbor(of: "v", .left) == "t")
    #expect(right(0.5, down(0.3, leaf("t"), leaf("u")), leaf("v")).neighbor(of: "v", .left) == "u")
    #expect(uneven.neighbor(of: "u", .up) == "t")
}
