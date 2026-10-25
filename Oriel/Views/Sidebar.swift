#if os(macOS)
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
        @SceneStorage("agentSort") private var sort = AgentSort.priority
        @State private var filter = ""
        /// The page in view, as the scroll view has it.
        @State private var position = ScrollPosition(idType: String.self)
        /// For a swipe's lift. Not state: a scroll or a slide redraws nothing (a state set as the slide began held
        /// its first frames).
        @State private var swipe = Swipe()
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
                    .background(ScrollAnchor(lift: lift))
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition($position)
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: Double.self) {
                    $0.contentOffset.x / max($0.containerSize.width, 1)
                } action: {
                    swipe.pages = $1
                }
                .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x } action: { Latency.shared.slid($1) }
                .onScrollPhaseChange { old, phase, context in
                    Latency.shared.scrolled(old, phase, context)
                    // A mouse's wheel, which pages with the system's snap.
                    if phase == .idle, !swipe.sliding, let id = position.viewID(type: String.self),
                       id != pages.current?.id,
                       let page = pages.list.first(where: { $0.id == id })
                    {
                        pages.show(page)
                    }
                }
                // A dot, a key, a new page or the sheet: slide there with the session spring.
                .onChange(of: pages.current?.id, initial: true) { old, new in
                    guard let new, position.viewID(type: String.self) != new else { return }
                    let still = reduceMotion && !Animation.forceMotion
                    withAnimation(old == nil || still ? nil : .session()) { position.scrollTo(id: new) }
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
                .padding(Sidebar.rowInsets)
                .padding(.top, 8)
            }
        }
    }

    /// One session's page: its name and `+`, then its workspace rows; or its Agents view and sort menu.
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
        /// ⌃⌘ held for 0.7 s: keycaps on the first nine workspaces (their jump keys).
        @State private var hints = false

        var body: some View {
            let store = page.store
            let rowsDrop = RowsDrop(page: page, frames: frames, state: $drop, reorders: filter.isEmpty)
            VStack(alignment: .leading, spacing: 0) {
                // The name and the sort menu's label on one baseline; the `+` has no text to align.
                HStack(alignment: agents == nil ? .center : .firstTextBaseline) {
                    // A long session name gives way in its middle.
                    // The page's title: the rows' size, bold (user, phase 27).
                    Text(store.title).truncationMode(.middle)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                        .accessibilityIdentifier("sidebar.header")
                    Spacer()
                    if let agents {
                        SortMenu(sort: agents)
                    } else {
                        IconButton(symbol: "plus", help: "New Workspace") { Task { await page.newWorkspace() } }
                            .disabled(store.state != .live)
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
                // Agents view: the name starts where the group labels and row icons do (the rows' insets and their
                // 8 pt padding).
                .padding(.leading, agents == nil ? 22 : Sidebar.rowInsets.leading + 8)
                // The `+` and the sort capsule end where the rows do: the sort label's text where the times end.
                .padding(.trailing, Sidebar.rowInsets.trailing)
                // Rex's first row sits 31.5 pt below the header's baseline.
                .padding(.bottom, 3)
                .contentShape(.rect)
                // The herdr session keeps running.
                .contextMenu { Button("Detach Session") { pages.close(page) }.disabled(pages.list.count < 2) }
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
                                             ends: (groups.first?.first?.id, groups.last?.first?.id),
                                             keycap: hints ? page.sidebarWorkspaces.prefix(9)
                                                 .firstIndex { $0.id == id }.map { $0 + 1 } : nil)
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
                        .padding(Sidebar.rowInsets)
                    }
                    .scrollIndicators(.never)
                    .keycapHints([.command, .control], $hints)
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

    private struct SortMenu: View {
        @Binding var sort: AgentSort

        var body: some View {
            Menu {
                Picker("Sort", selection: $sort) {
                    Text("Priority").tag(AgentSort.priority)
                    Text("Workspace").tag(AgentSort.workspace)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text("\(Image(systemName: "arrow.up.arrow.down")) \(sort.rawValue.capitalized)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 8)
                    .frame(height: 22)
            }
            .menuStyle(.button)
            // A small button, as the header buttons: a capsule filled on hover (user, phase 27).
            .buttonStyle(ChromeStyle(radius: 11))
            // Whole: the session's name gives way.
            .fixedSize()
            .accessibilityIdentifier("agents.sort")
            .accessibilityValue(sort.rawValue)
        }
    }

    /// A session with no workspace, in the page and in the strip: the button that makes one.
    struct NewWorkspaceButton: View {
        let page: Page

        var body: some View {
            Button("New Workspace", systemImage: "plus") { Task { await page.newWorkspace() } }
                .accessibilityIdentifier("new-workspace")
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

    final class Swipe {
        /// The pages' offset, in pages.
        var pages = 0.0
        /// A swipe's slide to its page, until the window shows that session.
        var sliding = false
    }

    extension Sidebar {
        /// A swipe's lift (the router hands it over, with the fingers' speed in points a second): the pages slide on
        /// from that speed to the next page that way, or back to the nearest one when slow, with the session spring;
        /// the window shows that session as the slide ends. The system's own snap took about 0.4 s (too slow, phase
        /// 25). Showing the session at the lift held the main thread for its first draw, and a slide started from the
        /// scroll view's own end waited for its snap: the pages stood still 100–350 ms, then jumped (phase 27).
        func lift(_ speed: Double) {
            let width = max(Double(width - gap), 1), page = swipe.pages
            let near = abs(speed) < 100 ? page.rounded() : speed > 0 ? page.rounded(.up) : page.rounded(.down)
            let index = min(max(Int(near), 0), pages.list.count - 1)
            guard pages.list.indices.contains(index) else { return }
            let target = pages.list[index], still = reduceMotion && !Animation.forceMotion
            swipe.sliding = true
            let slide = Animation.session(speed: speed / width, distance: Double(index) - page)
            withAnimation(still ? nil : slide, completionCriteria: .removed) {
                position.scrollTo(id: target.id)
            } completion: {
                swipe.sliding = false
                if target !== pages.current {
                    pages.show(target)
                }
            }
        }
    }

    extension Animation {
        /// The sidebar's session pages: between the tab spring and phase 25's 0.14 s, which the user found too quick
        /// and odd (phase 27), with no bounce. A swipe's slide starts at the fingers' `speed` toward the page
        /// `distance`
        /// away (in pages a second, and pages), so it goes on from the lift instead of starting again from rest.
        static func session(speed: Double = 0, distance: Double = 0) -> Animation {
            // Critically damped, it would go past the page from a relative speed over ω = 2π / response.
            let response = 0.2, initial = distance == 0 ? 0 : min(max(speed / distance, 0), 2 * .pi / response)
            return .interpolatingSpring(duration: response, bounce: 0, initialVelocity: initial)
        }
    }
#endif
