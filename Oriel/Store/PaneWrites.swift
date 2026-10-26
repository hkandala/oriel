import Foundation
import HerdrKit

/// Layout writes: panes and splits (phase 17), tab and workspace order (phases 13, 14, 18); each is one `write`,
/// then a snapshot read.
extension HostStore {
    /// Split Right or Down, or Left or Up (`before`): herdr splits only right and down, so a swap puts the new pane
    /// first. Then the run of same-direction splits holding the new pane is evened out, from herdr's tree after
    /// the split, as Rex does (33 / 33 / 33, not herdr's 50 / 25 / 25).
    /// Shown at once with an empty card for the new pane (phase 25), until a snapshot has herdr's. The pane may be an
    /// earlier split's stand-in (phase 29): its write, before this one, made herdr's. Returns the new pane, nil when
    /// herdr made none.
    func split(_ paneID: String, _ direction: SplitNode.Direction, before: Bool = false,
               standIn: String = Ahead.standIn()) async -> HerdrKit.Pane?
    {
        let tab = workspaces.flatMap(\.tabs).first { $0.tree?.paneIDs.contains(paneID) == true }
        if let tab, let tree = tab.tree {
            let known = Set(tree.paneIDs + (last?.trees[tab.id]?.paneIDs ?? []))
            ahead.split = Ahead.NewSplit(
                tabID: tab.id,
                standIn: standIn,
                tree: tree.split(paneID, direction, new: standIn, before: before),
                known: known,
            )
            redraw()
        }
        var made: HerdrKit.Pane?
        let done = await write { client in
            let paneID = ahead.splitPanes[paneID] ?? paneID
            guard let new = try await client.split(paneID, direction) else { return }
            made = new
            // Here, not after `write`: the next write may start first.
            ahead.splitPanes[standIn] = new.id
            if before {
                try await client.swap(paneID, direction == .right ? .right : .down)
            }
            try await even(client, tab: new.tabID, around: new.id)
        }
        // Not a later split's stand-in, which took the slot.
        if ahead.split?.standIn == standIn {
            ahead.split?.after = 0
            if !done {
                ahead.split = nil
                redraw()
            }
        }
        return made
    }

    /// The run of splits holding the pane evened out, from herdr's tree now.
    private func even(_ client: any Multiplexer, tab tabID: String, around paneID: String) async throws {
        for change in try await client.snapshot().trees[tabID]?.evened(around: paneID) ?? [] {
            try await client.setRatio(tab: tabID, path: change.path, ratio: change.ratio)
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

    /// Two cards of one tab trade places (a drop on a card's center).
    func swap(_ paneID: String, with targetID: String) async {
        await write { try await $0.swap(paneID, with: targetID) }
    }

    /// A drop beside a card (an edge), or on a tab's capsule (no target: right of the tab's last card, as herdr would
    /// split its focused pane, wherever that is). herdr splits only right or down, so a left or top edge swaps after;
    /// it refuses a move into the pane's own tab, so the pane goes to a new tab first. Then the run of splits holding
    /// it is evened out, as after a split. If a later step fails, the pane stays where it got to and the notice says
    /// so. The pane where it went.
    func place(_ paneID: String, in tabID: String, beside targetID: String? = nil,
               _ edge: Heading = .right) async -> HerdrKit.Pane?
    {
        var placed: HerdrKit.Pane?
        let targetID = targetID ?? workspace(of: tabID)?.tabs.first { $0.id == tabID }?.tree?.paneIDs.last
        await write { client in
            var id = paneID, done: String?
            do {
                if pane(paneID)?.tabID == tabID, let workspaceID = workspace(of: tabID)?.id {
                    guard let away = try await client.move(pane: id, to: .newTab(workspaceID: workspaceID))
                    else { throw HerdrError.failed("herdr named no pane") }
                    id = away.id
                    done = "Moved the pane to a new tab"
                }
                let split: SplitNode.Direction = edge == .left || edge == .right ? .right : .down
                guard let moved = try await client.move(pane: id, to: .tab(tabID, beside: targetID, split: split))
                else { throw HerdrError.failed("herdr named no pane") }
                placed = moved
                if let targetID, edge == .left || edge == .up {
                    done = "Moved the pane beside the card"
                    try await client.swap(moved.id, with: targetID)
                }
                done = nil
                try await even(client, tab: tabID, around: moved.id)
            } catch {
                throw done.map { HerdrError.failed("\($0): herdr refused the next step") } ?? error
            }
        }
        return placed
    }

    /// The pane where it went: a move to another workspace gives it a new id.
    func move(_ paneID: String, to destination: Destination) async -> HerdrKit.Pane? {
        var moved: HerdrKit.Pane?
        await write { moved = try await $0.move(pane: paneID, to: destination) }
        return moved
    }

    /// The tab, with its panes, split tree and ratios, to another workspace of the session, last there. herdr 0.9.5's
    /// `tab.move` stays inside a workspace, so its first pane goes to a new tab there (with its label, unless herdr's
    /// number) and each other pane beside one moved before (`SplitNode.rebuild`); each move gives a new pane id.
    /// The tree is herdr's when the write's turn comes (a write before it may change the tab). The source tab closes
    /// with its last pane, its workspace with its last tab. A failed step leaves the panes where they got to. Each
    /// pane where it went, by its old id, the first pane first.
    func move(tab tabID: String, to workspaceID: String) async -> [(old: String, new: HerdrKit.Pane)] {
        guard let tab = workspace(of: tabID)?.tabs.first(where: { $0.id == tabID }),
              tab.tree?.paneIDs.contains(where: Ahead.isStandIn) == false else { return [] }
        let label = tab.label.allSatisfy(\.isNumber) ? nil : tab.label
        var moved: [(old: String, new: HerdrKit.Pane)] = []
        await write { client in
            guard let tree = try await client.snapshot().trees[tabID]
            else { throw HerdrError.failed("herdr has no such tab") }
            do {
                guard let first = try await client.move(pane: tree.paneIDs[0],
                                                        to: .newTab(workspaceID: workspaceID, label: label))
                else { throw HerdrError.failed("herdr named no pane") }
                moved = [(tree.paneIDs[0], first)]
                for step in tree.rebuild {
                    guard let beside = moved.first(where: { $0.old == step.beside })?.new.id,
                          let pane = try await client.move(
                              pane: step.paneID,
                              to: .tab(first.tabID, beside: beside, split: step.direction, ratio: step.ratio),
                          ) else { throw HerdrError.failed("herdr named no pane") }
                    moved.append((step.paneID, pane))
                }
            } catch {
                throw moved.isEmpty ? error : HerdrError.failed("Moved part of the tab: herdr refused the next step")
            }
        }
        return moved
    }

    /// Trimmed; an empty label clears it; nothing when the same.
    func rename(pane paneID: String, label: String) async {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard label != pane(paneID)?.label ?? "" else { return }
        await write { try await $0.rename(pane: paneID, label: label.isEmpty ? nil : label) }
    }

    /// One place left (-1) or right (1); none past the ends (a snapshot may land after the menu opened).
    func move(tab tabID: String, by offset: Int) async {
        guard let tabs = workspace(of: tabID)?.tabs, let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs.indices.contains(index + offset) else { return }
        // herdr inserts before the tab now at the index, so one place right is two on.
        await move(tab: tabID, to: index + (offset > 0 ? 2 : -1))
    }

    /// Before the tab now at `index` (the count puts it last).
    func move(tab tabID: String, to index: Int) async {
        await write { try await $0.move(tab: tabID, to: index) }
    }

    /// One row group (a workspace and its worktrees) up (-1) or down (1) past the next group; none past the ends.
    func move(workspace workspaceID: String, by offset: Int) async {
        let groups = groups
        guard let index = groups.firstIndex(where: { $0.first?.id == workspaceID }),
              groups.indices.contains(index + offset) else { return }
        let before = offset < 0 ? groups[index - 1].first?.id : groups.indices.contains(index + 2)
            ? groups[index + 2].first?.id : nil
        await move(workspaces: groups[index].map(\.id), before: before)
    }

    /// The workspaces, in this order, before another one, or last.
    func move(workspaces workspaceIDs: [String], before workspaceID: String?) async {
        await write { try await $0.move(workspaces: workspaceIDs, before: workspaceID) }
    }
}
