import Foundation
import HerdrKit

/// What the app shows before herdr has it: a close, a new tab and a split draw at once, and the snapshots after them
/// confirm it; a replaced pane's new pane hides until the old one is gone. A closing pane, tab or workspace is left
/// out until a snapshot no longer has it; a new tab or a split shows an empty card under a stand-in id until a
/// snapshot has what herdr made. A failed write takes it back.
struct Ahead {
    /// Panes, tabs and workspaces being closed. herdr never gives a closed id to a new one while its server runs.
    var closing: Set<String> = []
    /// New tabs not in a snapshot yet, oldest first.
    var tabs: [NewTab] = []
    var split: NewSplit?
    /// herdr's panes for split stand-ins, while one shows: a split of a stand-in (⌘D pressed fast) splits its pane.
    var splitPanes: [String: String] = [:]
    /// herdr's tabs that took stand-ins' places in the last snapshot, by stand-in id: every page's selection and tab
    /// history follow them as they settle on that snapshot.
    var arrived: [String: String] = [:]
    /// herdr's tabs that took a stand-in's place, while they last: a close of one whose shell still starts shows at
    /// once (quick ⌘W after quick ⌘T). Not every starting pane: a program run in a pane split a second ago
    /// would hide, then come back with the question.
    var fresh: Set<String> = []
    /// herdr's tabs for stand-ins closed before they came: the store closes them.
    var toClose: [String] = []
    /// Replace Pane's old panes, by id. Every new pane of the old one's tab hides while the old one is there, so the
    /// new pane shows in the old one's place in one snapshot, never beside it first.
    var replacing: [String: Replacing] = [:]
    /// The replacements done in the last snapshot, by old pane id: every page's zoom and floating window follow them.
    var replaced: [String: Replacing] = [:]
    /// Replaced panes by new id, while it is there: the strip's next render, maybe after more shows, keeps the card.
    var cards: [String: String] = [:]

    struct NewTab {
        let id: String, workspaceID: String
        /// The workspace's tabs when it was asked for, and the ones other stand-ins took since.
        var known: Set<String>
        /// Closed before herdr's tab came: it is closed as it comes.
        var closed = false
        /// herdr's answer: its tab, shown in the stand-in's place once a snapshot has it.
        var made: String?
    }

    /// The tab's tree with the stand-in, its panes before the split, and the snapshots since herdr answered (nil
    /// until then).
    struct NewSplit {
        let tabID: String, standIn: String, tree: SplitNode, known: Set<String>
        var after: Int?
    }

    static func standIn() -> String {
        "new.\(UUID().uuidString)"
    }

    static func isStandIn(_ id: String) -> Bool {
        id.hasPrefix("new.")
    }

    /// herdr's tab for the stand-in, from its answer or a snapshot: no other stand-in may take it.
    mutating func made(_ standIn: String, _ id: String) {
        arrived[standIn] = id
        fresh.insert(id)
        if tabs.first(where: { $0.id == standIn })?.closed == true {
            closing.insert(id)
            toClose.append(id)
        }
        tabs.removeAll { $0.id == standIn }
        for index in tabs.indices {
            tabs[index].known.insert(id)
        }
    }

    /// The snapshot as the app shows it.
    struct Shown {
        var workspaces: [Workspace]
        var tabs: [Tab]
        var panes: [HerdrKit.Pane]
        var trees: [String: SplitNode]
    }

    mutating func show(_ snapshot: Snapshot) -> Shown {
        let ids = snapshot.workspaces.map(\.id) + snapshot.tabs.map(\.id) + snapshot.panes.map(\.id)
        closing.formIntersection(ids)
        fresh.formIntersection(ids)
        arrived = [:]
        replaced = replacing.filter { !ids.contains($0.key) }
        keepCards(ids)
        replacing = replacing.filter { ids.contains($0.key) }
        let hidden = closing.union(replacing.values.flatMap { $0.hidden(snapshot.panes) })
        // herdr's tab for each stand-in: the first new one of its workspace.
        tabs.removeAll { standIn in !snapshot.workspaces.contains { $0.id == standIn.workspaceID } }
        for id in tabs.map(\.id) {
            // Read again: `made` adds to the others' known tabs.
            guard let standIn = tabs.first(where: { $0.id == id }), let tab = snapshot.tabs.first(where: { tab in
                standIn.made.map { $0 == tab.id }
                    ?? (tab.workspaceID == standIn.workspaceID && !standIn.known.contains(tab.id))
            }) else { continue }
            made(id, tab.id)
        }
        var trees = snapshot.trees.compactMapValues { $0.removing(hidden) }
        if let split {
            let now = snapshot.trees[split.tabID]
            let even = now.flatMap { tree in
                tree.paneIDs.first { !split.known.contains($0) }.map { tree.evened(around: $0).isEmpty }
            } == true
            // Once herdr answered: the first snapshot with its pane evened, else the second (a ratio herdr kept its own
            // way, or a snapshot read before the answer).
            if now == nil || split.after.map({ $0 > 0 || even }) == true {
                self.split = nil
            } else {
                trees[split.tabID] = split.tree.removing(closing)
                self.split?.after = split.after.map { $0 + 1 }
            }
        }
        if split == nil {
            splitPanes = [:]
        }
        // A tab whose last pane closes closes, and a workspace whose last tab closes.
        let emptied = Set(snapshot.trees.keys).subtracting(trees.keys)
        var tabs = snapshot.tabs.filter {
            !closing.contains($0.id) && !closing.contains($0.workspaceID) && !emptied.contains($0.id)
        }
        let left = Set(tabs.map(\.workspaceID)), had = Set(snapshot.tabs.map(\.workspaceID))
        let workspaces = snapshot.workspaces.filter {
            !closing.contains($0.id) && (left.contains($0.id) || !had.contains($0.id))
        }
        let shownTabs = Set(tabs.map(\.id))
        let panes = snapshot.panes.filter { !hidden.contains($0.id) && shownTabs.contains($0.tabID) }
        for standIn in self.tabs where !standIn.closed && workspaces.contains(where: { $0.id == standIn.workspaceID }) {
            tabs.append(Tab(id: standIn.id, workspaceID: standIn.workspaceID, label: ""))
            trees[standIn.id] = .leaf(paneID: standIn.id)
        }
        return Shown(workspaces: workspaces, tabs: tabs, panes: panes, trees: trees)
    }
}

/// Closes (design D41), shown at once.
extension HostStore {
    /// Closes at once when every pane of it runs only its shell; else the close to ask about, with what runs (design
    /// D41), for the asking window. Asked now, not the panes' last answers: a program may have started since. When the
    /// last answers say only shells run, or a new tab's shell still starts, it is gone at once, before this returns,
    /// while herdr is asked (quick ⌘W after quick ⌘T step back one tab each); a program found brings it
    /// back with the question. Any other pane with no answer yet waits for herdr's. Nil: nothing to ask.
    func ask(_ request: Close) -> Task<Closing?, Never>? {
        guard let client else { return nil }
        // Stand-ins only (⌘T, then a close before herdr answered; a new tab's card has its tab's id) go now, herdr's
        // tabs as they come.
        let ids = closeIDs(request), standIns = ids.filter(Ahead.isStandIn)
        if !ids.isEmpty, standIns.count == ids.count {
            closeStandIns(standIns)
            return nil
        }
        let tabs = tabIDs(request)
        let asked = panes.filter { pane in request.paneID.map { $0 == pane.id } ?? tabs.contains(pane.tabID) }
        let action = closing(request)
        // ponytail: a program typed in a new tab in its first seconds hides too, and comes back with the question.
        let clear = asked.allSatisfy {
            $0.program?.isShell == true || $0.plugin != nil && $0.program?.isPlaceholder == true
                || $0.starting && ahead.fresh.contains($0.tabID)
        }
        if clear {
            hide(request)
        }
        let starting = Set(asked.filter(\.starting).map(\.id))
        return Task {
            let running = await programs(asked.map(\.id), starting: starting,
                                         placeholders: Set(asked.filter { $0.plugin != nil }.map(\.id)), client)
            // Sorted: "A program" leads the list.
            guard running.isEmpty else {
                if clear {
                    unhide(request)
                }
                return Closing(close: request, running: running.sorted())
            }
            // Close Other Tabs: the stand-ins among them too, once it goes ahead.
            closeStandIns(standIns)
            await close(request, action)
            return nil
        }
    }

    private func closeStandIns(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        for index in ahead.tabs.indices where ids.contains(ahead.tabs[index].id) {
            ahead.tabs[index].closed = true
        }
        redraw()
    }

    /// What runs besides the shells in the panes, asked now, 8 at a time: a big workspace is not 30 herdr runs at once.
    /// A new pane's shell still starting runs short-lived programs (`ls`, `sort`, as after ⌘T): asked again for up to
    /// 0.8 s until only its shell runs. ponytail: a slower startup (a cold nvm) still asks, naming what it runs.
    /// `placeholders`: browser panes, whose placeholder runs no program (any process can label a pane, so only the
    /// placeholder counts).
    func programs(_ paneIDs: [String], starting: Set<String>, placeholders: Set<String> = [],
                  _ client: any Multiplexer) async -> Set<String>
    {
        await withTaskGroup(of: String?.self) { group in
            var rest = paneIDs[...]
            func next() {
                guard let id = rest.popFirst() else { return }
                group.addTask {
                    let ask = {
                        try await client.program(id).flatMap {
                            $0.isShell || placeholders.contains(id) && $0.isPlaceholder ? nil : $0.title
                        }
                    }
                    do {
                        var name = try await ask()
                        for _ in 0 ..< (starting.contains(id) ? 4 : 0) where name != nil {
                            try await Task.sleep(for: .milliseconds(200))
                            name = try await ask()
                        }
                        return name
                    } catch {
                        // Unknown: ask.
                        return "A program"
                    }
                }
            }
            for _ in 0 ..< 8 {
                next()
            }
            var names = Set<String>()
            for await name in group {
                if let name {
                    names.insert(name)
                }
                next()
            }
            return names
        }
    }

    /// The tabs a close of tabs or a workspace takes, as the user sees them now; none for a pane.
    func tabIDs(_ close: Close) -> [String] {
        switch close {
        case .pane: []
        case let .tab(id): [id]
        case let .otherTabs(ids, _): ids
        case let .workspace(id):
            (workspaces.filter { $0.id == id } + worktrees(of: id)).flatMap(\.tabs).map(\.id)
        }
    }

    /// The user said yes: gone at once, then herdr closes it; a failed close brings it back.
    func close(_ close: Close) async {
        await self.close(close, closing(close))
    }

    private func close(_ close: Close, _ action: @escaping (any Multiplexer) async throws -> Void) async {
        hide(close)
        if await !write(action) {
            unhide(close)
        }
    }

    /// The close's herdr calls, from what shows now (before it is hidden).
    private func closing(_ close: Close) -> (any Multiplexer) async throws -> Void {
        switch close {
        case let .pane(id):
            // The device that closes a browser pane removes its state file (future-work/plugins/state).
            let state = pane(id)?.browser?.statePath(session: session), machine = machine
            return { client in
                try await client.close(pane: id)
                if let state {
                    await machine.exec().remove(home: state)
                }
            }
        case let .tab(id): return { try await $0.close(tab: id) }
        case let .otherTabs(asked, _):
            // Not ones closed meanwhile (their close would fail the rest), and all at once: one by one, 20 tabs took
            // seconds and the bar showed each step.
            let others = asked.filter { workspace(of: $0) != nil && !Ahead.isStandIn($0) }
            return { client in
                try await withThrowingTaskGroup { group in
                    for other in others {
                        group.addTask { try await client.close(tab: other) }
                    }
                    try await group.waitForAll()
                }
            }
        case let .workspace(id):
            // herdr refuses to close a repository's workspace with open worktrees unless the group goes too.
            let group = workspaces.contains { $0.id == id } && !worktrees(of: id).isEmpty
            return { try await $0.close(workspace: id, group: group) }
        }
    }

    /// The close shown at once: what it takes is left out until herdr has closed it.
    func hide(_ close: Close) {
        ahead.closing.formUnion(closeIDs(close))
        redraw()
    }

    func unhide(_ close: Close) {
        ahead.closing.subtract(closeIDs(close))
        redraw()
    }

    /// The ids a close takes away: herdr closes a workspace's worktrees with it (`HostStore.close`).
    private func closeIDs(_ close: Close) -> [String] {
        switch close {
        case let .pane(id), let .tab(id): [id]
        case let .otherTabs(ids, _): ids
        case let .workspace(id): [id] + worktrees(of: id).map(\.id)
        }
    }

    /// A new tab shown at once in the workspace, last, as "New Tab"; its stand-in id.
    func standIn(in workspaceID: String) -> String {
        let id = Ahead.standIn()
        let known = (last?.tabs ?? []).filter { $0.workspaceID == workspaceID }.map(\.id)
        ahead.tabs.append(Ahead.NewTab(id: id, workspaceID: workspaceID, known: Set(known)))
        redraw()
        return id
    }

    func dropStandIn(_ id: String) {
        ahead.tabs.removeAll { $0.id == id }
        redraw()
    }

    /// herdr answered with the stand-in's tab: the stand-in shows until a snapshot has it, and no other stand-in
    /// takes it.
    func madeTab(_ standIn: String, _ id: String) {
        for index in ahead.tabs.indices {
            if ahead.tabs[index].id == standIn {
                ahead.tabs[index].made = id
            } else {
                ahead.tabs[index].known.insert(id)
            }
        }
    }

    /// The tabs of stand-ins closed before herdr made them: already left out, closed now.
    func closeArrived() {
        let ids = ahead.toClose
        ahead.toClose = []
        for id in ids {
            Task { await close(.tab(id)) }
        }
    }
}
