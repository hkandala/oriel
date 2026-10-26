/// One tab's split tree, as herdr stores it.
public indirect enum SplitNode: Equatable, Sendable {
    case leaf(paneID: String)
    case split(Direction, ratio: Double, first: SplitNode, second: SplitNode)

    public enum Direction: String, Decodable, Sendable {
        case right, down

        /// herdr has only these two; anything else draws side by side rather than failing the snapshot.
        public init(from decoder: any Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .right
        }
    }

    /// Rebuilds the tree from `snapshot.layouts[]`: a split's id is `split_<n>_<path>` with one digit
    /// per step from the root (`0` first, `1` second), and `panes[]` is depth-first. Nil when the
    /// leaves do not match the panes; then ask herdr with `layout.export`.
    init?(_ layout: Layout) {
        let splits = Dictionary(layout.splits.map { split in
            let path = split.id.split(separator: "_").last.map(String.init) ?? ""
            return (path == "root" ? "" : path, split)
        }, uniquingKeysWith: { first, _ in first })
        var panes = layout.panes.map(\.pane_id)[...]
        func build(_ path: String) -> SplitNode? {
            guard let split = splits[path] else { return panes.popFirst().map { .leaf(paneID: $0) } }
            guard let first = build(path + "0"), let second = build(path + "1") else { return nil }
            return .split(split.direction, ratio: split.ratio, first: first, second: second)
        }
        guard let root = build(""), panes.isEmpty else { return nil }
        self = root
    }
}

/// The nested form `layout.export` returns.
extension SplitNode: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, paneID = "pane_id", direction, ratio, first, second
    }

    public init(from decoder: any Decoder) throws {
        let node = try decoder.container(keyedBy: CodingKeys.self)
        if try node.decode(String.self, forKey: .type) == "split" {
            self = try .split(
                node.decode(Direction.self, forKey: .direction),
                ratio: node.decode(Double.self, forKey: .ratio),
                first: node.decode(SplitNode.self, forKey: .first),
                second: node.decode(SplitNode.self, forKey: .second),
            )
        } else {
            self = try .leaf(paneID: node.decode(String.self, forKey: .paneID))
        }
    }
}

/// Equal splits (like Rex): in a run of same-direction splits, n panes get 1/n each.
public extension SplitNode {
    /// The leaves, first to last (herdr's `panes[]` order).
    var paneIDs: [String] {
        switch self {
        case let .leaf(id): [id]
        case let .split(_, _, first, second): first.paneIDs + second.paneIDs
        }
    }

    /// The moves that build the tree again in another tab once its first pane is there (herdr 0.9.5 moves no tab to
    /// another workspace): each puts a pane beside one placed before, split that way at the split's ratio. Top down,
    /// so the pane it goes beside holds the whole split's place then.
    var rebuild: [Move] {
        guard case let .split(direction, ratio, first, second) = self else { return [] }
        return [Move(paneID: second.paneIDs[0], beside: first.paneIDs[0], direction: direction, ratio: ratio)]
            + first.rebuild + second.rebuild
    }

    struct Move: Sendable {
        public let paneID, beside: String
        public let direction: Direction
        public let ratio: Double
    }

    /// The tree as herdr makes it when it splits the pane: the pane and the new one share its place (the new one
    /// second,
    /// or first when `before`), then the run holding the new one evened out, as `HostStore.split` asks.
    func split(_ paneID: String, _ direction: Direction, new newID: String, before: Bool) -> SplitNode {
        let pair: (SplitNode, SplitNode) = before ? (.leaf(paneID: newID), .leaf(paneID: paneID))
            : (.leaf(paneID: paneID), .leaf(paneID: newID))
        let split = replacing(paneID, with: .split(direction, ratio: 0.5, first: pair.0, second: pair.1))
        return split.evened(around: newID).reduce(split) { tree, change in tree.setting(change.ratio, at: change.path) }
    }

    private func replacing(_ paneID: String, with node: SplitNode) -> SplitNode {
        switch self {
        case let .leaf(id): id == paneID ? node : self
        case let .split(direction, ratio, first, second):
            .split(direction, ratio: ratio, first: first.replacing(paneID, with: node),
                   second: second.replacing(paneID, with: node))
        }
    }

    private func setting(_ new: Double, at path: [Bool]) -> SplitNode {
        guard case let .split(direction, ratio, first, second) = self else { return self }
        guard let step = path.first else { return .split(direction, ratio: new, first: first, second: second) }
        let rest = Array(path.dropFirst())
        return step ? .split(direction, ratio: ratio, first: first, second: second.setting(new, at: rest))
            : .split(direction, ratio: ratio, first: first.setting(new, at: rest), second: second)
    }

    /// The tree without these panes: a split that loses one side becomes its other side, as herdr closes a pane. Nil
    /// when none is left.
    func removing(_ paneIDs: Set<String>) -> SplitNode? {
        switch self {
        case let .leaf(id): paneIDs.contains(id) ? nil : self
        case let .split(direction, ratio, first, second):
            switch (first.removing(paneIDs), second.removing(paneIDs)) {
            case let (first?, second?): .split(direction, ratio: ratio, first: first, second: second)
            case let (first?, nil): first
            case let (nil, second): second
            }
        }
    }

    /// The ratio changes that even out the run of same-direction splits holding the pane (all runs when nil):
    /// each split gets the units on its first side over the units under it, where a child split in the other
    /// direction counts as one unit. Paths as `layout.set_split_ratio` takes them (`false` = first child).
    func evened(around paneID: String? = nil) -> [(path: [Bool], ratio: Double)] {
        guard let paneID else { return run([], whole: true) }
        guard let path = path(to: paneID), !path.isEmpty else { return [] }
        // The pane's parent, then up while the parent splits the same way.
        var top = Array(path.dropLast())
        let direction = node(at: top)?.direction
        while !top.isEmpty, node(at: Array(top.dropLast()))?.direction == direction {
            top.removeLast()
        }
        return node(at: top)?.run(top, whole: false) ?? []
    }

    private var direction: Direction? {
        if case let .split(direction, _, _, _) = self {
            direction
        } else {
            nil
        }
    }

    private func units(_ direction: Direction) -> Int {
        if case let .split(own, _, first, second) = self, own == direction {
            first.units(direction) + second.units(direction)
        } else {
            1
        }
    }

    /// This split's run (its children that split the same way, and theirs), or every split below when `whole`.
    private func run(_ path: [Bool], whole: Bool) -> [(path: [Bool], ratio: Double)] {
        guard case let .split(direction, ratio, first, second) = self else { return [] }
        let even = Double(first.units(direction)) / Double(units(direction))
        let own = abs(even - ratio) > 0.001 ? [(path, even)] : []
        return own + [(first, false), (second, true)].flatMap { child, step in
            whole || child.direction == direction ? child.run(path + [step], whole: whole) : []
        }
    }

    private func path(to paneID: String) -> [Bool]? {
        switch self {
        case let .leaf(id): id == paneID ? [] : nil
        case let .split(_, _, first, second):
            first.path(to: paneID).map { [false] + $0 } ?? second.path(to: paneID).map { [true] + $0 }
        }
    }

    private func node(at path: [Bool]) -> SplitNode? {
        guard let step = path.first else { return self }
        guard case let .split(_, _, first, second) = self else { return nil }
        return (step ? second : first).node(at: Array(path.dropFirst()))
    }
}
