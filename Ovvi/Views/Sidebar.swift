import HerdrKit
import SwiftUI

/// Arc-style pages, one per session open in the window (D43), paged sideways; page dots, the filter and Open
/// Session at the bottom. Each page lists its session's workspaces like herdr's Spaces panel.
struct Sidebar: View {
    static let widths: ClosedRange<Double> = 227 ... 480
    /// Rex's rows: 10 pt in from the window's edge.
    static let rowInsets = EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 3)

    let pages: WindowPages
    /// The Agents view instead of the workspaces.
    let agents: Bool
    @Binding var width: Double
    let openSession: () -> Void
    @State private var filter = ""
    @State private var swipe = Swipe()
    /// The pages' frame in the window, for the router.
    @State private var area = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            pagesAndFooter
                // On the window background, as in the reference: only the pane cards are lighter.
                .frame(width: width - gap)
            ResizeHandle(width: $width)
        }
        .foregroundStyle(look.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar")
        // e2e: made when it shows, not when the overview closes.
        .onAppear { Latency.shared.note("sidebar made") }
    }

    private var pagesAndFooter: some View {
        VStack(spacing: 0) {
            Pager(swipe: swipe, width: width - gap) {
                HStack(spacing: 0) {
                    // At rest only the page in view (`Pager`): the others would lie over the tab's page, in the
                    // sidebar's accessibility frame (which takes in laid-out views past the clip) and in AppKit's
                    // hit tests.
                    ForEach(swipe.moving ? pages.list : pages.list.filter { $0 === pages.current }) { page in
                        SidebarPage(page: page, pages: pages, filter: filter, agents: agents)
                            .frame(width: width - gap)
                            .accessibilityHidden(page !== pages.current)
                            .allowsHitTesting(page === pages.current)
                            .transition(.identity)
                    }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area = $0 }
            // Not under the overview, which hides it.
            .background(PagesAnchor(
                step: step,
                drag: pages.overview ? nil : drag as (Double, Bool) -> Void,
                lift: lift,
                agent: agents && !pages.overview
                    ? { offset in pages.current.map { AgentsList.step(offset, $0) } }
                    : nil,
                area: area,
            ))
            // A dot, a key, a new page or the sheet: slide there with the session spring. A swipe is there already.
            // Under the overview at once: hidden, it would draw both pages for 0.3 s.
            .onChange(of: pages.list.map(\.id) + [pages.current?.id ?? ""], initial: true) { old, new in
                guard let index = pages.list.firstIndex(where: { $0 === pages.current }),
                      swipe.slide != Double(index) else { return }
                let slides = old.last != new.last && !pages.overview && !(reduceMotion && !Animation.forceMotion)
                slide(to: index, with: slides ? .session() : nil)
            }
            if pages.list.count > 1 {
                PageDots(pages: pages)
            }
            HStack(spacing: 2) {
                FilterField(prompt: "Filter", text: $filter, identifier: "sidebar.filter")
                    .onExitCommand { filter = "" }
                    .padding(.trailing, 4)
                IconButton(symbol: "plus.square.on.square", help: "Open Session", key: .openSession,
                           action: openSession)
                    .accessibilityIdentifier("sidebar.open-session")
            }
            .padding(Sidebar.rowInsets)
            .padding(.top, 8)
        }
    }
}

/// One session's page: its name and `+`, then its workspace rows; or its name and its Agents view.
private struct SidebarPage: View {
    let page: Page
    let pages: WindowPages
    let filter: String
    /// The Agents view instead of the workspaces.
    let agents: Bool
    typealias Row = (workspace: HostStore.Workspace, parent: HostStore.Workspace?)

    /// Rows above or below the scrolled list's edges, for the fades.
    @State private var under = (top: false, bottom: false)
    /// Each row's frame in the list's visible space, for drops; measured while nothing is dragged.
    @State private var frames: [String: CGRect] = [:]
    @State private var drop = RowsDrop.State()
    /// The workspace dropped last: its rows glide into their place.
    @State private var landing: Landing?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A pane or a tab dragged over the header's `+`.
    @State private var plus = false
    /// ⌘ or ⌃⌘ held for 0.7 s: keycaps on the first nine workspaces (their jump keys).
    @State private var hints = false
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        let store = page.store
        let rowsDrop = RowsDrop(page: page, frames: frames, state: $drop, reorders: filter.isEmpty) { rows, offset in
            if !reduceMotion || Animation.forceMotion {
                landing = Landing(ids: rows, offset: offset, count: (landing?.count ?? 0) + 1)
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // The rows' size, bold; a long session name gives way in its middle.
                Text(store.title).truncationMode(.middle)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                    .accessibilityIdentifier("sidebar.header")
                    // The `+`'s height in both views, so the name stays put.
                    .frame(height: 28)
                    // A right-click on it reaches the row's menu.
                    .allowsHitTesting(false)
                Spacer()
                if !agents {
                    IconButton(symbol: "plus", help: "New Workspace") { Task { await page.newWorkspace() } }
                        .disabled(store.state != .live)
                        .accessibilityIdentifier("sidebar.new-workspace")
                        // A new workspace, as the ghost row under the rows, which a full page has no room for.
                        .overlay {
                            if plus, page.dragging != nil {
                                DropIndicator(radius: 7)
                            }
                        }
                        .onDrop(of: [.ovviDrag], delegate: PaneDrop(page: page, target: .move(.newWorkspace()),
                                                                    over: $plus))
                        .clearsDrop(page) { plus = false }
                }
            }
            // On one edge in both views: the workspace rows' names, the Agents view's tiles and shelf labels.
            .padding(.leading, Sidebar.rowInsets.leading + WorkspaceRow.textInset)
            // The `+` ends where the rows do.
            .padding(.trailing, Sidebar.rowInsets.trailing)
            // Rex's first row sits 31.5 pt below the header's baseline.
            .padding(.bottom, 3)
            // The herdr session keeps running. Behind the row: on the row, a menu takes the row's frame for the name
            // when it is the row's only element (the Agents view).
            .background {
                Color.clear.contentShape(.rect)
                    .contextMenu { Button("Detach Session") { pages.close(page) }.disabled(pages.list.count < 2) }
            }
            if agents {
                AgentsList(page: page, filter: filter)
            } else if store.state == .live, store.workspaces.isEmpty {
                Button("New Workspace", systemImage: "plus") { Task { await page.newWorkspace() } }
                    .accessibilityIdentifier("new-workspace")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        let rows = rows, groups = store.groups
                        ForEach(Array(rows.enumerated()), id: \.element.workspace.id) { index, row in
                            let id = row.workspace.id
                            WorkspaceRow(workspace: row.workspace, parent: row.parent, page: page,
                                         guideBelow: rows.indices.contains(index + 1)
                                             && rows[index + 1].parent != nil,
                                         ends: (groups.first?.first?.id, groups.last?.first?.id),
                                         keycap: hints ? page.sidebarWorkspaces.prefix(9)
                                             .firstIndex { $0.id == id }.map { $0 + 1 } : nil)
                                .overlay {
                                    if drop.over == id, page.dragging != nil {
                                        DropIndicator()
                                    }
                                }
                                .opacity(page.lifted == .workspace(id) ? 0.4 : 1)
                                .offset(y: rowsDrop.shift(id))
                                .lands(id, landing, axis: .vertical)
                                // Its place in the list, outside the drag's slide and the drop's glide.
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
                                    frames[id] = $0
                                }
                                // Hidden by the filter or closed: no stale target.
                                .onDisappear { frames[id] = nil }
                                .background { Color.clear.id("into view \(id)").padding(.vertical, -18) }
                        }
                        if drop.ghost, page.dragging != nil {
                            Text("New Workspace").foregroundStyle(.secondary).padding(.leading, WorkspaceRow.textInset)
                                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                                .background { DropIndicator() }
                        }
                        if rows.isEmpty, !store.workspaces.isEmpty {
                            Text("No matching workspaces").foregroundStyle(.secondary).padding(.vertical, 8)
                                .padding(.leading, WorkspaceRow.textInset)
                        }
                    }
                    .padding(Sidebar.rowInsets)
                }
                .scrollIndicators(.never)
                .scrollPosition($position)
                // The selected row and the fade's room round it (its background) into view, just enough, however
                // it was selected; again once laid out, for a row new in this update (a new page).
                .onChange(of: "into view \(page.selectedWorkspaceID ?? "")", initial: true) { _, id in
                    withTransaction(\.animation, nil) { position.scrollTo(id: id) }
                    Task { position.scrollTo(id: id) }
                }
                .keycapHints(.command, [.command, .control], shown: $hints)
                .coordinateSpace(.named("rows"))
                .onDrop(of: [.ovviDrag], delegate: rowsDrop)
                .clearsDrop(page) {
                    drop.spring?.cancel()
                    drop = RowsDrop.State()
                }
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    [geometry.contentOffset.y > 0.5,
                     geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5]
                } action: {
                    under = ($1[0], $1[1])
                }
                .fadeEdges(.vertical, start: under.top ? 18 : 0, end: under.bottom ? 18 : 0)
            }
        }
    }

    /// The rows that pass the filter by name or branch, each with the workspace it sits under; a matching
    /// worktree keeps its repository's row.
    private var rows: [Row] {
        page.store.groups.flatMap { group -> [Row] in
            let shown = group.filter { $0.label.matches(filter) || ($0.git?.branch ?? "").matches(filter) }
            guard let head = group.first, !shown.isEmpty else { return [] }
            return (shown.first === head ? shown : [head] + shown).map { Row($0, $0 === head ? nil : head) }
        }
    }
}

private struct PageDots: View {
    let pages: WindowPages

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages.list) { page in
                Button { pages.show(page) } label: {
                    Circle().fill(page === pages.current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                        // The gap is part of each dot's click area.
                        .frame(width: 12, height: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Detach Session") { pages.close(page) }.disabled(pages.list.count < 2) }
                .accessibilityLabel(page.store.title)
                .accessibilityIdentifier("sidebar.dot.\(page.id)")
                .accessibilityAddTraits(page === pages.current ? .isSelected : [])
            }
        }
        .padding(.top, 4)
    }
}

/// The handle at the sidebar's trailing edge, over the tab page's 8 pt gap: a drag resizes it in `Sidebar.widths`.
private struct ResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Color.clear.frame(width: gap).contentShape(.rect)
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
                let start = start ?? width
                self.start = start
                resize(to: start + drag.translation.width)
            }.onEnded { _ in start = nil })
            .accessibilityElement()
            .accessibilityLabel("Sidebar Width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { resize(to: width + ($0 == .increment ? 20 : -20)) }
            .accessibilityIdentifier("sidebar.resize")
    }

    private func resize(to value: Double) {
        width = min(max(value, Sidebar.widths.lowerBound), Sidebar.widths.upperBound)
    }
}

extension Sidebar {
    /// The router's moves of a sideways swipe (in points, toward later pages): the pages follow the fingers from
    /// where they are drawn (a slide stops), and stop at the first and last page. Not under a panel (the palette,
    /// Open Session), which would then act on another page.
    private func drag(_ delta: Double, first: Bool) {
        guard !pages.panelOpen else { return }
        let width = max(width - gap, 1), last = Double(max(pages.list.count - 1, 0))
        if first {
            swipe.moves += 1
            // Mid-slide: from where the pages are drawn.
            if swipe.moving {
                swipe.slide = swipe.drawn / width
            }
            swipe.moving = true
        }
        swipe.slide = min(max(swipe.slide + delta / width, 0), last)
    }

    /// A mouse's sideways wheel: the next or previous page.
    private func step(_ offset: Int) {
        if !pages.panelOpen {
            pages.step(offset)
        }
    }

    /// A swipe's lift, with the fingers' speed in points a second: the pages slide on from that speed to the next
    /// page that way, or to the nearest one when slow, with the session spring; the window shows that session as
    /// the pages arrive. The pages are the app's own: a scroll view's paging snap took about 0.4 s, and on a quick
    /// flick stood still until a timeout, then snapped back while the window showed the other session.
    private func lift(_ speed: Double) {
        let width = max(width - gap, 1), page = swipe.slide
        let index = Swipe.landing(page, speed: speed, count: pages.list.count)
        guard pages.list.indices.contains(index) else { return }
        let target = pages.list[index]
        Latency.shared.lifted(page * width)
        // Shown once the pages arrive; shown at the lift, the session held the slide's first frames.
        let still = reduceMotion && !Animation.forceMotion
        slide(to: index, with: still ? nil : .session(speed: speed / width, distance: Double(index) - page)) {
            if target !== pages.current {
                Latency.shared.shown()
                pages.show(target)
            }
        }
    }

    /// The pages slide to the page at `index` (or go, with no animation); `then` runs as they arrive, unless
    /// another move took them meanwhile.
    private func slide(to index: Int, with animation: Animation?, then: @escaping () -> Void = {}) {
        swipe.moves += 1
        let move = swipe.moves
        // No move (a flick at the first or last page), no animation: it might never end.
        guard let animation, swipe.slide != Double(index) else {
            swipe.slide = Double(index)
            swipe.moving = false
            then()
            return
        }
        let slide = {
            withAnimation(animation, completionCriteria: .logicallyComplete) {
                swipe.slide = Double(index)
            } completion: {
                if swipe.moves == move {
                    swipe.moving = false
                    then()
                }
            }
        }
        guard swipe.moving else {
            // The other pages first, in an update of their own: in the slide's, their offset from rest would too.
            swipe.moving = true
            Task {
                if swipe.moves == move {
                    slide()
                }
            }
            return
        }
        slide()
    }
}
