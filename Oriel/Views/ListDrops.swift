import HerdrKit
import SwiftUI

/// A drag over the tab track. A pane over another tab's capsule highlights it and spring-loads it after 0.65 s; a
/// drop moves the pane into that tab. Its own tab's capsule is not a target (herdr refuses `same_tab`). A tab of
/// the workspace goes to the place under the pointer (`tab.move`).
struct TrackDrop: DropDelegate {
    let tabs: [HostStore.Tab]
    let page: Page
    /// A capsule and its divider.
    let slot: CGFloat
    @Binding var over: Int?
    @Binding var spring: Task<Void, Never>?
    let springLoad: (String) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        switch page.dragging {
        case .pane: true
        case let .tab(id): tabs.contains { $0.id == id }
        default: false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // A late update after the drag ended.
        guard page.dragging != nil else { return nil }
        let place = info.location.x / max(slot, 1)
        if let id = page.dragging?.paneID {
            let index = min(max(Int(place), 0), tabs.count - 1)
            guard tabs.indices.contains(index), page.store.pane(id)?.tabID != tabs[index].id else {
                dropExited(info: info)
                return DropProposal(operation: .forbidden)
            }
            if over != index {
                withAnimation(.highlight) { over = index }
                spring?.cancel()
                let tabID = tabs[index].id
                spring = springTask(page) { springLoad(tabID) }
            }
        } else {
            let index = min(max(Int(place.rounded()), 0), tabs.count)
            if over != index {
                withAnimation(.slide) { over = index }
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        spring?.cancel()
        // A tab slides back; a capsule's highlight fades.
        withAnimation(page.dragging?.paneID == nil ? .slide : .highlight) { over = nil }
    }

    func performDrop(info _: DropInfo) -> Bool {
        spring?.cancel()
        defer { over = nil }
        guard let over else { return false }
        switch page.dragging {
        case let .pane(id):
            // A snapshot during the drag may have closed tabs.
            guard tabs.indices.contains(over) else { return false }
            Task { await page.drop(id, on: .tab(tabs[over].id)) }
        case let .tab(id):
            // herdr inserts before the tab now at the index; its own place or the next is no move.
            if let from = tabs.firstIndex(where: { $0.id == id }), over != from, over != from + 1 {
                Task { await page.store.move(tab: id, to: over) }
            }
        default:
            return false
        }
        return true
    }
}

/// A workspace menu row (the collapsed sidebar's): a pane or a tab of the page dropped on it goes to a new tab in
/// that workspace, or on New Workspace to a new workspace, as in the sidebar, highlighted the same; no spring-load
/// in a menu.
struct MenuRowDrop: ViewModifier {
    struct Target {
        let page: Page
        let destination: Destination
        /// The menu is open. It is there, hidden, through the whole drag: macOS 27 finds no drop target added
        /// after the drag entered the window.
        let shown: Bool
    }

    let target: Target?
    @State private var over = false

    func body(content: Content) -> some View {
        // Only during a drag: a drop target on the row at other times cost it the pointer's light on CI (one run
        // in two).
        if let target, target.page.dragging != nil {
            content
                .overlay {
                    if over {
                        DropIndicator(radius: 8)
                    }
                }
                .onDrop(of: [.orielDrag], delegate: PaneDrop(
                    page: target.page, target: .move(target.destination), over: $over,
                    enabled: target.shown,
                ))
        } else {
            content
        }
    }
}

/// A drag over a page's workspace rows. A pane over a row highlights it and spring-loads it after 0.65 s; a drop
/// moves it to a new tab there. A tab over another workspace's row highlights it, and a drop moves the tab there
/// whole; no spring-load (that workspace's tab row would not take it). A pane or a tab dropped under the last row
/// goes to a new workspace. A dragged workspace goes to the place under the pointer, its worktrees with it; a
/// worktree moves only among its repository's worktrees.
struct RowsDrop: DropDelegate {
    struct State {
        /// The row a pane or a tab is over.
        var over: String?
        /// A pane or a tab under the last row.
        var ghost = false
        /// Where a dragged workspace goes, among its blocks.
        var slot: Int?
        var spring: Task<Void, Never>?
    }

    let page: Page
    let frames: [String: CGRect]
    @Binding var state: State
    /// Not while the filter hides rows: a reorder needs them all.
    let reorders: Bool

    func validateDrop(info _: DropInfo) -> Bool {
        switch page.dragging {
        case .pane, .tab: true
        case .workspace: reorders
        case nil: false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // A late update after the drag ended.
        guard page.dragging != nil else { return nil }
        let pointY = info.location.y
        if case let .workspace(id) = page.dragging {
            let index = blocks(id).count { block in middle(block) < pointY }
            if state.slot != index {
                withAnimation(.slide) { state.slot = index }
            }
            return DropProposal(operation: .move)
        }
        let pane = page.dragging?.paneID != nil
        let ghost = pointY > frames.values.map(\.maxY).max() ?? 0
        if ghost != state.ghost {
            withAnimation(.highlight) { state.ghost = ghost }
        }
        // A tab's own workspace is not a target.
        let home: HostStore.Workspace? = if case let .tab(id) = page.dragging {
            page.store.workspace(of: id)
        } else {
            nil
        }
        // The 2 pt gaps count as the row above.
        let row = state.ghost ? nil : page.store.workspaces.first { workspace in
            frames[workspace.id].map { pointY >= $0.minY && pointY < $0.maxY + 2 } ?? false && workspace !== home
        }
        if row?.id != state.over {
            withAnimation(.highlight) { state.over = row?.id }
            state.spring?.cancel()
            if let row, pane {
                state.spring = springTask(page) { page.select(row) }
            }
        }
        return DropProposal(operation: row == nil && !state.ghost ? .forbidden : .move)
    }

    func dropExited(info _: DropInfo) {
        state.spring?.cancel()
        withAnimation(state.slot == nil ? .highlight : .slide) { state = State() }
    }

    func performDrop(info _: DropInfo) -> Bool {
        let dropped = state
        state.spring?.cancel()
        state = State()
        switch page.dragging {
        case let .pane(id):
            guard let target: DropTarget = dropped.ghost ? .move(.newWorkspace())
                : dropped.over.map({ .move(.newTab(workspaceID: $0)) }) else { return false }
            Task { await page.drop(id, on: target) }
        case let .tab(id):
            guard dropped.ghost || dropped.over != nil else { return false }
            Task { await page.drop(tab: id, on: dropped.over) }
        case let .workspace(id):
            let blocks = blocks(id)
            guard let slot = dropped.slot, let from = blocks.firstIndex(where: { $0.contains { $0.id == id } }),
                  slot != from, slot != from + 1 else { return false }
            Task { await page.store.move(workspaces: blocks[from].map(\.id), before: before(slot, blocks)) }
        default:
            return false
        }
        return true
    }

    /// A dragged workspace slides to its place and the blocks it passes slide the other way by its height.
    func shift(_ id: String) -> CGFloat {
        guard case let .workspace(dragged) = page.dragging, let slot = state.slot else { return 0 }
        let blocks = blocks(dragged)
        guard let from = blocks.firstIndex(where: { $0.contains { $0.id == dragged } }),
              let index = blocks.firstIndex(where: { $0.contains { $0.id == id } }) else { return 0 }
        // A snapshot during the drag may have closed workspaces.
        let place = min(slot > from ? slot - 1 : slot, blocks.count - 1)
        if index == from {
            return place > from ? blocks[from + 1 ... place].map(height).reduce(0, +)
                : -blocks[place ..< from].map(height).reduce(0, +)
        }
        return from < index && index <= place ? -height(blocks[from])
            : place <= index && index < from ? height(blocks[from]) : 0
    }

    /// What a workspace moves among: the row groups, or for a worktree its repository's other worktrees.
    private func blocks(_ id: String) -> [[HostStore.Workspace]] {
        let groups = page.store.groups
        if let group = groups.first(where: { $0.dropFirst().contains { $0.id == id } }) {
            return group.dropFirst().map { [$0] }
        }
        return groups
    }

    /// Rows and their 2 pt gaps.
    private func height(_ block: [HostStore.Workspace]) -> CGFloat {
        block.compactMap { frames[$0.id]?.height }.reduce(0, +) + 2 * CGFloat(block.count)
    }

    private func middle(_ block: [HostStore.Workspace]) -> CGFloat {
        let rows = block.compactMap { frames[$0.id] }
        return ((rows.map(\.minY).min() ?? 0) + (rows.map(\.maxY).max() ?? 0)) / 2
    }

    /// The workspace a block dropped at `slot` goes before: the block there, else (last) none for groups, and for
    /// worktrees the workspace after the last one in herdr's order.
    private func before(_ slot: Int, _ blocks: [[HostStore.Workspace]]) -> String? {
        if blocks.indices.contains(slot) {
            return blocks[slot].first?.id
        }
        let all = page.store.workspaces
        guard let last = blocks.last?.last, page.store.parent(of: last) != nil,
              let index = all.firstIndex(where: { $0 === last }), all.indices.contains(index + 1)
        else { return nil }
        return all[index + 1].id
    }
}

extension Page {
    /// A dragged tab dropped on another workspace or (nil) a new one: the page follows it there, and its keyboard
    /// card keeps the keyboard.
    func drop(tab tabID: String, on workspaceID: String?) async {
        let keyboard = keyboardCard(tabID)
        let moved = await store.move(tab: tabID, to: workspaceID)
        let pane = moved.first { $0.old == keyboard?.id }?.new ?? moved.first?.new
        follow(pane, pane?.terminalID)
    }
}
