#if os(macOS)
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
                    withAnimation(.easeOut(duration: 0.12)) { over = index }
                    spring?.cancel()
                    let tabID = tabs[index].id
                    spring = Task {
                        // Not after the drag ended (a late update).
                        if await (try? Task.sleep(for: springDelay)) != nil, page.dragging?.paneID != nil {
                            springLoad(tabID)
                        }
                    }
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
            withAnimation(page.dragging?.paneID == nil ? .slide : .easeOut(duration: 0.12)) { over = nil }
        }

        func performDrop(info _: DropInfo) -> Bool {
            spring?.cancel()
            defer { over = nil }
            guard let over else { return false }
            switch page.dragging {
            case let .pane(id):
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

    /// A drag over a page's workspace rows. A pane over a row highlights it and spring-loads it after 0.65 s; a drop
    /// moves it to a new tab there, and a drop under the last row to a new workspace. A dragged workspace goes to the
    /// place under the pointer, its worktrees with it; a worktree moves only among its repository's worktrees. A tab
    /// is not taken: herdr moves a tab only inside its workspace.
    struct RowsDrop: DropDelegate {
        struct State {
            /// The row a pane is over.
            var over: String?
            /// A pane under the last row.
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
            case .pane: true
            case .workspace: reorders
            default: false
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
            let ghost = pointY > frames.values.map(\.maxY).max() ?? 0
            if ghost != state.ghost {
                withAnimation(.easeOut(duration: 0.12)) { state.ghost = ghost }
            }
            // The 2 pt gaps count as the row above.
            let row = state.ghost ? nil : page.store.workspaces.first { workspace in
                frames[workspace.id].map { pointY >= $0.minY && pointY < $0.maxY + 2 } ?? false
            }
            if row?.id != state.over {
                withAnimation(.easeOut(duration: 0.12)) { state.over = row?.id }
                state.spring?.cancel()
                if let row {
                    state.spring = Task {
                        // Not after the drag ended (a late update).
                        if await (try? Task.sleep(for: springDelay)) != nil, page.dragging?.paneID != nil {
                            page.select(row)
                        }
                    }
                }
            }
            return DropProposal(operation: row == nil && !state.ghost ? .forbidden : .move)
        }

        func dropExited(info _: DropInfo) {
            state.spring?.cancel()
            withAnimation(page.dragging?.paneID == nil ? .slide : .easeOut(duration: 0.12)) { state = State() }
        }

        func performDrop(info _: DropInfo) -> Bool {
            let dropped = state
            state.spring?.cancel()
            state = State()
            switch page.dragging {
            case let .pane(id):
                guard let target: DropTarget = dropped.ghost ? .move(.newWorkspace)
                    : dropped.over.map({ .move(.newTab(workspaceID: $0)) }) else { return false }
                Task { await page.drop(id, on: target) }
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
            let place = slot > from ? slot - 1 : slot
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
#endif
