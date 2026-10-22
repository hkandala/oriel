import HerdrKit

/// Pane and layout writes (phase 17); each is one `write`, then a snapshot read.
extension HostStore {
    /// Split Right or Down, or Left or Up (`before`): herdr splits only right and down, so a swap puts the new pane
    /// first. Then the run of same-direction splits holding the new pane is evened out, from herdr's tree after
    /// the split, as Rex does (33 / 33 / 33, not herdr's 50 / 25 / 25).
    func split(_ paneID: String, _ direction: SplitNode.Direction, before: Bool = false) async {
        await write { client in
            guard let new = try await client.split(paneID, direction) else { return }
            if before {
                try await client.swap(paneID, direction == .right ? .right : .down)
            }
            let tree = try await client.snapshot().trees[new.tabID]
            for change in tree?.evened(around: new.id) ?? [] {
                try await client.setRatio(tab: new.tabID, path: change.path, ratio: change.ratio)
            }
        }
    }

    /// Every run of the tab evened out (Balance Splits).
    func balance(_ tab: Tab) async {
        let changes = tab.tree?.evened() ?? []
        await write { client in
            for change in changes {
                try await client.setRatio(tab: tab.id, path: change.path, ratio: change.ratio)
            }
        }
    }

    /// One divider's ratio, kept in herdr's 0.1–0.9. Whether herdr took it.
    func setRatio(tab tabID: String, path: [Bool], ratio: Double) async -> Bool {
        await write { try await $0.setRatio(tab: tabID, path: path, ratio: min(max(ratio, 0.1), 0.9)) }
    }

    /// The keyboard card's nearest divider that way, 5 %.
    func resize(_ paneID: String, _ heading: Heading) async {
        await write { try await $0.resize(paneID, heading, amount: 0.05) }
    }

    func swap(_ paneID: String, _ heading: Heading) async {
        await write { try await $0.swap(paneID, heading) }
    }

    /// The pane where it went: a move to another workspace gives it a new id.
    func move(_ paneID: String, to destination: Destination) async -> HerdrKit.Pane? {
        var moved: HerdrKit.Pane?
        await write { moved = try await $0.move(pane: paneID, to: destination) }
        return moved
    }

    /// An empty label clears it.
    func rename(pane paneID: String, label: String) async {
        await write { try await $0.rename(pane: paneID, label: label.isEmpty ? nil : label) }
    }
}
