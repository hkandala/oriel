import Foundation
import HerdrKit

/// A new tab right after a tab: a linked open (⌘-click, Open in New Tab), a link's new tab and `ovvi open --tab`.
/// herdr adds a tab last and the app then moves it (`tab.move`); the bar shows it right after its tab from the first
/// snapshot that has it, never at the end first.
extension Ahead {
    struct Beside {
        let id = UUID(), workspaceID: String, after: String
        /// The workspace's tabs when it was asked for, and the ones other new tabs took since: the first other tab of
        /// the workspace is the new one, until herdr names it.
        var known: Set<String>
        var tab: String?
        /// The snapshots since herdr answered the move (nil until then).
        var answered: Int?
    }

    /// The tabs with each new tab right after its tab, until herdr's order is the one shown or its tab is gone; herdr's
    /// order shows from the third snapshot after its answer at the latest, so a move herdr put elsewhere (a stale
    /// index, a drag, another client) never pins the tab.
    /// ponytail: a tab another client makes, or a ⌘T's stand-in claims, before herdr names the new one can take its
    /// place, and a redraw counts as a snapshot; name it from a tab event if that shows.
    mutating func placed(_ tabs: [Tab], herdr: [Tab]) -> [Tab] {
        beside.removeAll { $0.answered.map { $0 >= 2 } ?? false }
        for index in beside.indices where beside[index].tab == nil {
            let new = beside[index]
            if let tab = tabs.first(where: { $0.workspaceID == new.workspaceID && !new.known.contains($0.id) }) {
                name(new.id, tab.id)
            }
        }
        var tabs = tabs
        for new in beside {
            guard let from = tabs.firstIndex(where: { $0.id == new.tab }) else { continue }
            let tab = tabs.remove(at: from)
            tabs.insert(tab, at: tabs.firstIndex { $0.id == new.after }.map { $0 + 1 } ?? from)
        }
        let ids = tabs.map(\.id), shown = Set(ids)
        let done = herdr.map(\.id).filter(shown.contains) == ids
        // Not before the snapshot has it: herdr's answer can name it first.
        beside.removeAll { new in
            new.tab.map { shown.contains($0) && (done || !shown.contains(new.after)) } ?? false
        }
        for index in beside.indices {
            beside[index].answered = beside[index].answered.map { $0 + 1 }
        }
        return tabs
    }

    /// herdr's tab for the new tab: no other new tab or stand-in takes it.
    mutating func name(_ id: UUID, _ tab: String) {
        for index in beside.indices {
            if beside[index].id == id {
                beside[index].tab = tab
            } else {
                beside[index].known.insert(tab)
            }
        }
        for index in tabs.indices {
            tabs[index].known.insert(tab)
        }
    }
}

extension HostStore {
    /// Shows the next new tab of the workspace right after tab `after` (`Ahead.Beside`); its id. Not one another
    /// new tab claimed: a second quick open starts before a snapshot has the first one's tab.
    func placeBeside(_ after: String, in workspaceID: String) -> UUID {
        let herdrs = (last?.tabs ?? []).filter { $0.workspaceID == workspaceID }.map(\.id)
        let claimed = ahead.beside.compactMap(\.tab) + ahead.tabs.compactMap(\.made)
        let new = Ahead.Beside(workspaceID: workspaceID, after: after, known: Set(herdrs + claimed))
        ahead.beside.append(new)
        return new.id
    }

    /// herdr made the new tab, last: it moves it right after `after`. A failed move leaves it at the end, still open.
    func moveBeside(_ id: UUID, _ tab: String, after: String, in workspaceID: String, _ client: any Multiplexer) async {
        ahead.name(id, tab)
        // herdr inserts before the tab now at the index.
        let herdrs = (last?.tabs ?? []).filter { $0.workspaceID == workspaceID }.map(\.id)
        if let index = herdrs.firstIndex(of: after) {
            do {
                try await client.move(tab: tab, to: index + 1)
            } catch {
                dropBeside(id)
            }
        }
        if let index = ahead.beside.firstIndex(where: { $0.id == id }) {
            ahead.beside[index].answered = 0
        }
    }

    /// Other tabs show as herdr has them.
    func dropBeside(_ id: UUID) {
        ahead.beside.removeAll { $0.id == id }
        redraw()
    }
}
