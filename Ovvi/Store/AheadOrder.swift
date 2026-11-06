import Foundation

extension Ahead {
    /// The snapshots since herdr answered (nil until then): the first with the order, else the second, ends it (a
    /// snapshot may be read before the answer). `workspaceID`: the tabs' workspace; nil for the workspaces.
    struct NewOrder {
        let workspaceID: String?, ids: [String]
        var after: Int?
    }

    /// The items `mine` takes in the asked order, until herdr's matches it or one of them came or went.
    /// ponytail: one that comes before herdr's answer (a ⌘T's tab) ends it early, and a redraw counts as a snapshot
    /// (`after`): the old order can show until herdr's answer. Keep the asked order for its items if that shows.
    static func ordered<T>(_ items: [T], by order: inout NewOrder?, id: (T) -> String, mine: (T) -> Bool) -> [T] {
        guard let asked = order else { return items }
        let indices = items.indices.filter { mine(items[$0]) }
        let ids = indices.map { id(items[$0]) }
        guard ids != asked.ids, Set(ids) == Set(asked.ids), asked.after.map({ $0 < 1 }) ?? true else {
            order = nil
            return items
        }
        order?.after = asked.after.map { $0 + 1 }
        var items = items
        let byID = Dictionary(indices.map { (id(items[$0]), items[$0]) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in zip(indices, asked.ids) {
            items[index] = byID[id] ?? items[index]
        }
        return items
    }
}
