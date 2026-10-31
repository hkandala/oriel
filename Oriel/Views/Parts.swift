import HerdrKit
import SwiftUI

/// Where each card and divider of the tree goes: each split divides its rectangle by its ratio, less the 8 pt gap,
/// which is its divider. Both sides get an exact size, so no card's content can push its neighbor out of the page.
struct Parts {
    struct Card {
        let id: String
        let rect: CGRect
        /// Where it slides in from: beside its place, on its side of its split.
        let start: CGRect
    }

    struct Divider {
        /// From the root, `false` = first child, as `layout.set_split_ratio` takes it.
        let path: [Bool]
        let right: Bool
        let rect: CGRect
        /// The split's length without the gap.
        let total: CGFloat
        /// herdr's, kept in 0–1 (a NaN or out-of-range ratio from herdr must not break the layout).
        let ratio: Double
        /// The last pane of the first side and the first of the second.
        let beside: [String?]

        /// The path in `0` and `1` digits, `root` for the root split.
        var id: String {
            path.isEmpty ? "root" : path.map { $0 ? "1" : "0" }.joined()
        }
    }

    private(set) var cards: [Card] = []
    private(set) var dividers: [Divider] = []

    init(_ tree: SplitNode, in area: CGRect, held: [[Bool]: Double]) {
        add(tree, area, path: [], side: CGVector(dx: 1, dy: 0), held: held)
    }

    /// `side`: the card's side of its split, as a unit step (right, left, down or up).
    private mutating func add(_ node: SplitNode, _ rect: CGRect, path: [Bool], side: CGVector,
                              held: [[Bool]: Double])
    {
        switch node {
        case let .leaf(id):
            let start = rect.offsetBy(dx: side.dx * (rect.width + gap), dy: side.dy * (rect.height + gap))
            cards.append(Card(id: id, rect: rect, start: start))
        case let .split(direction, ratio, first, second):
            let right = direction == .right, from: CGRectEdge = right ? .minXEdge : .minYEdge
            let total = max(0, (right ? rect.width : rect.height) - gap)
            let herdr = ratio.isNaN ? 0.5 : min(max(ratio, 0), 1)
            let (one, rest) = rect.divided(atDistance: total * (held[path] ?? herdr), from: from)
            let (line, two) = rest.divided(atDistance: gap, from: from)
            add(first, one, path: path + [false], side: right ? CGVector(dx: -1, dy: 0) : CGVector(dx: 0, dy: -1),
                held: held)
            dividers.append(Divider(path: path, right: right, rect: line, total: total, ratio: herdr,
                                    beside: [first.paneIDs.last, second.paneIDs.first]))
            add(second, two, path: path + [true], side: right ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1),
                held: held)
        }
    }
}
