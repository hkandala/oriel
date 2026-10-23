#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// Arc-style pages, one per session open in the window (D43), paged sideways; page dots, the filter and Open
    /// Session at the bottom. Each page lists its session's workspaces like herdr's Spaces panel.
    struct Sidebar: View {
        static let widths: ClosedRange<Double> = 227 ... 480

        let pages: WindowPages
        /// The Agents view instead of the workspaces.
        let agents: Bool
        @Binding var width: Double
        let openSession: () -> Void
        @SceneStorage("agentSort") private var sort = AgentSort.priority
        @State private var filter = ""
        /// The page in view, as the scroll view has it.
        @State private var position = ScrollPosition(idType: String.self)
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
        }

        private var pagesAndFooter: some View {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(pages.list) { page in
                            SidebarPage(page: page, pages: pages, filter: filter, agents: agents ? $sort : nil)
                                .containerRelativeFrame(.horizontal)
                                // Only the page in view, for VoiceOver and the tests: the others are off to the side.
                                .accessibilityHidden(page !== pages.current)
                                .environment(\.offscreen, page !== pages.current)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition($position)
                .scrollIndicators(.never)
                .onScrollPhaseChange { _, phase in
                    if phase == .idle, let id = position.viewID(type: String.self), id != pages.current?.id,
                       let page = pages.list.first(where: { $0.id == id })
                    {
                        pages.show(page)
                    }
                }
                // A dot, a new page or the sheet: slide there with the strip's spring.
                .onChange(of: pages.current?.id, initial: true) { old, new in
                    guard let new, position.viewID(type: String.self) != new else { return }
                    withAnimation(old == nil || reduceMotion ? nil : .tab) { position.scrollTo(id: new) }
                    // A page that opened lays out in this same update, and a scroll to it can miss.
                    Task { position.scrollTo(id: new) }
                }
                if pages.list.count > 1 {
                    PageDots(pages: pages)
                }
                HStack(spacing: 2) {
                    FilterField(prompt: "Filter", text: $filter, identifier: "sidebar.filter")
                        .onExitCommand { filter = "" }
                        .padding(.trailing, 4)
                    IconButton(
                        symbol: "plus.square.on.square",
                        help: "Open Session",
                        key: .openSession,
                        action: openSession,
                    )
                    .accessibilityIdentifier("sidebar.open-session")
                }
                .padding(.leading, 10)
                .padding(.trailing, 3)
                .padding(.vertical, 8)
            }
        }
    }

    /// One session's page: its name and `+`, then its workspace rows.
    private struct SidebarPage: View {
        let page: Page
        let pages: WindowPages
        let filter: String
        /// The Agents view's order while it is on.
        let agents: Binding<AgentSort>?
        typealias Row = (workspace: HostStore.Workspace, parent: HostStore.Workspace?)

        /// Rows above or below the scrolled list's edges, for the fades.
        @State private var under = (top: false, bottom: false)
        /// Each row's frame in the list's visible space, for drops; measured while nothing is dragged.
        @State private var frames: [String: CGRect] = [:]
        @State private var drop = RowsDrop.State()
        /// A pane dragged over the header's `+`.
        @State private var plus = false

        var body: some View {
            let store = page.store
            let rowsDrop = RowsDrop(page: page, frames: frames, state: $drop, reorders: filter.isEmpty)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // A long session name gives way in its middle; " · agents" stays.
                    HStack(spacing: 0) {
                        Text(page.id).truncationMode(.middle)
                        if agents != nil {
                            Text(" · agents").fixedSize()
                        }
                    }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    // Before the sort menu's label, which gives way first.
                    .layoutPriority(1)
                    .accessibilityElement(children: .ignore).accessibilityAddTraits(.isStaticText)
                    .accessibilityValue(agents == nil ? page.id : "\(page.id) · agents")
                    .accessibilityIdentifier("sidebar.header")
                    Spacer()
                    if let agents {
                        SortMenu(sort: agents)
                    } else {
                        IconButton(symbol: "plus", help: "New Workspace") { Task { await page.newWorkspace() } }
                            .disabled(store.state != .live || store.writing)
                            .accessibilityIdentifier("sidebar.new-workspace")
                            // A new workspace, as the ghost row under the rows, which a full page has no room for.
                            .overlay {
                                if plus, page.dragging != nil {
                                    DropIndicator(radius: 7)
                                }
                            }
                            .onDrop(of: [.orielDrag], delegate: PaneDrop(page: page, target: .move(.newWorkspace),
                                                                         over: $plus))
                            .clearsDrop(page) { plus = false }
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 3)
                .contentShape(.rect)
                .contextMenu { ClosePage(page: page, pages: pages) }
                if let agents {
                    AgentsList(page: page, filter: filter, sort: agents.wrappedValue)
                } else if store.state == .live, store.workspaces.isEmpty {
                    NewWorkspaceButton(page: page).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            let rows = rows, groups = store.groups
                            ForEach(Array(rows.enumerated()), id: \.element.workspace.id) { index, row in
                                let id = row.workspace.id
                                WorkspaceRow(workspace: row.workspace, parent: row.parent, page: page,
                                             guideBelow: rows.indices.contains(index + 1)
                                                 && rows[index + 1].parent != nil,
                                             ends: (groups.first?.first?.id, groups.last?.first?.id))
                                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
                                        if page.dragging == nil {
                                            frames[id] = $0
                                        }
                                    }
                                    // Hidden by the filter or closed: no stale target.
                                    .onDisappear { frames[id] = nil }
                                    .overlay {
                                        if drop.over == id, page.dragging != nil {
                                            DropIndicator()
                                        }
                                    }
                                    .opacity(page.dragging == .workspace(id) ? 0.4 : 1)
                                    .offset(y: rowsDrop.shift(id))
                            }
                            if drop.ghost, page.dragging != nil {
                                Text("New Workspace").foregroundStyle(.secondary).padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                                    .background { DropIndicator() }
                            }
                            if rows.isEmpty, !store.workspaces.isEmpty {
                                Text("No matching workspaces").foregroundStyle(.secondary).padding(8)
                            }
                        }
                        // Rex's rows: 10 pt in from the window's edge.
                        .padding(.leading, 10)
                        .padding(.trailing, 3)
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.never)
                    .coordinateSpace(.named("rows"))
                    .onDrop(of: [.orielDrag], delegate: rowsDrop)
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
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [under.top ? .clear : .black, .black], startPoint: .top,
                                           endPoint: .bottom).frame(height: 18)
                            Rectangle()
                            LinearGradient(colors: [.black, under.bottom ? .clear : .black], startPoint: .top,
                                           endPoint: .bottom).frame(height: 18)
                        }
                    }
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

    /// The Agents view's order: Priority or Workspace order.
    private struct SortMenu: View {
        @Binding var sort: AgentSort

        var body: some View {
            Menu {
                Picker("Sort", selection: $sort) {
                    Text("Priority").tag(AgentSort.priority)
                    Text("Workspace order").tag(AgentSort.workspace)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(
                    "\(Image(systemName: "arrow.up.arrow.down")) \(sort == .priority ? "Priority" : "Workspace order")",
                )
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 6)
                .frame(height: 22)
            }
            .menuStyle(.button)
            .buttonStyle(ChromeStyle(radius: 6))
            .accessibilityIdentifier("agents.sort")
            .accessibilityValue(sort.rawValue)
        }
    }

    /// The page's Close Page item (header and dot): the herdr session keeps running.
    private struct ClosePage: View {
        let page: Page
        let pages: WindowPages

        var body: some View {
            Button("Close Page") { pages.close(page) }.disabled(pages.list.count < 2)
        }
    }

    /// A session with no workspace, in the page and in the strip: the button that makes one.
    struct NewWorkspaceButton: View {
        let page: Page

        var body: some View {
            Button("New Workspace", systemImage: "plus") { Task { await page.newWorkspace() } }
                .disabled(page.store.writing)
                .accessibilityIdentifier("new-workspace")
        }
    }

    /// One 6 pt dot per page, 6 pt apart; a click shows that page.
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
                    .contextMenu { ClosePage(page: page, pages: pages) }
                    .accessibilityLabel(page.id)
                    .accessibilityIdentifier("sidebar.dot.\(page.id)")
                    .accessibilityAddTraits(page === pages.current ? .isSelected : [])
                }
            }
            .padding(.top, 4)
        }
    }

    /// The handle at the sidebar's trailing edge, beside the pages and over the strip's 8 pt gap: a drag resizes it
    /// within `Sidebar.widths`.
    private struct ResizeHandle: View {
        @Binding var width: Double
        @State private var start: Double?

        var body: some View {
            Color.clear.frame(width: gap).contentShape(.rect)
                .pointerStyle(.columnResize)
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
                    let start = start ?? width
                    self.start = start
                    width = min(max(start + drag.translation.width, Sidebar.widths.lowerBound),
                                Sidebar.widths.upperBound)
                }.onEnded { _ in start = nil })
                .accessibilityElement()
                .accessibilityLabel("Sidebar Width")
                .accessibilityIdentifier("sidebar.resize")
        }
    }
#endif
