#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// One full-size page per tab of the workspace, paged sideways. The selection follows the page in view when the
    /// scroll stops; a new selection (a click, a key) scrolls there, so the tab marker moves the same way either time.
    struct Strip: View {
        let workspace: HostStore.Workspace
        let page: Page
        /// The page in view, as the scroll view has it.
        @State private var position = ScrollPosition(idType: String.self)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        Group {
                            if let tree = tab.tree {
                                // Inside the scroll view, which clips: room for the cards' outer stroke and shadow.
                                SplitLayout(node: tree, page: page, tabID: tab.id)
                                    // Layout motion: splits, closes, moves and herdr's ratios; a drag follows the
                                    // pointer.
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tree)
                                    .padding([.horizontal, .bottom], gap)
                                    .padding(.top, 4)
                            } else {
                                Text("No layout for this tab").foregroundStyle(.secondary)
                            }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("page.\(tab.id)")
                    }
                }
                .scrollTargetLayout()
                .background(StripAnchor(page: page))
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition($position, anchor: .leading)
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Double.self) {
                // Within a point of a page, the strip rests on it (one lit tab): on CI (a 1x display) it once came to
                // rest just past the first page after the sidebar hid, with both capsules lit. Else to a thousandth.
                let width = max($0.containerSize.width, 1), page = $0.contentOffset.x / width
                return abs(page - page.rounded()) * width < 1 ? page.rounded() : (page * 1000).rounded() / 1000
            } action: {
                page.stripPage = $1
            }
            .onScrollPhaseChange { _, phase in
                // Not a page of the workspace that was shown before a switch.
                if phase == .idle, let shown = position.viewID(type: String.self),
                   workspace.tabs.contains(where: { $0.id == shown })
                {
                    page.selectedTabIDs[workspace.id] = shown
                }
            }
            // One strip for every workspace: a new one jumps to its selected tab, a new tab in the same one scrolls.
            .onChange(of: [workspace.id, page.selectedTabIDs[workspace.id]], initial: true) { old, new in
                guard let target = page.selectedTabIDs[workspace.id],
                      position.viewID(type: String.self) != target else { return }
                let animate = old != new && old.first == new.first && !reduceMotion
                // The tab marker follows the scroll.
                withAnimation(animate ? .tab : nil) { position.scrollTo(id: target, anchor: .leading) }
                if old.first != new.first {
                    // Another workspace's pages lay out in this same update, and a scroll to one of them can miss (a
                    // new workspace came up blank): scroll again once they have.
                    Task { position.scrollTo(id: target, anchor: .leading) }
                }
            }
        }
    }

    /// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one goes to
    /// the scroll view under the pointer (the strip, over a card), so a terminal never sees it; any other goes to the
    /// view under the pointer as usual. Its momentum follows. A wheel picks per event; Shift makes it sideways.
    @MainActor
    enum SwipeRouter {
        /// Once, at launch.
        static func install() {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated { route(event) } ? nil : event
            }
        }

        /// Every window's strip, for wheel clicks; each registers itself.
        fileprivate static let strips = NSHashTable<StripAnchor.Anchor>.weakObjects()
        /// Where the current sideways gesture goes; nil while it goes the usual way.
        private weak static var target: NSScrollView?
        private static var picked = false
        private static var moved = 0.0
        private static var wheeled = Date.distantPast

        /// Whether the event went to a scroll view or turned the strip.
        private static func route(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if event.phase.isEmpty, event.momentumPhase.isEmpty {
                return wheel(event, sideways: abs(deltaX) > abs(deltaY) ? deltaX : 0)
            }
            if event.phase == .began {
                picked = false
                target = nil
                moved = 0
            }
            if !picked {
                moved += abs(deltaX) + abs(deltaY)
                if moved >= 4 {
                    picked = true
                    target = abs(deltaX) > abs(deltaY) ? scrollView(event) : nil
                }
            }
            target?.scrollWheel(with: event)
            return target != nil
        }

        /// A sideways wheel step goes to the scroll view under the pointer; over the strip, a burst of line steps
        /// (a mouse, which would only nudge a paged strip) turns one page.
        private static func wheel(_ event: NSEvent, sideways deltaX: CGFloat) -> Bool {
            guard deltaX != 0, let scrollView = scrollView(event) else { return false }
            if !event.hasPreciseScrollingDeltas,
               let strip = strips.allObjects.first(where: { $0.enclosingScrollView === scrollView })
            {
                if Date.now.timeIntervalSince(wheeled) > 0.3 {
                    strip.step(deltaX > 0 ? -1 : 1)
                }
                wheeled = .now
            } else {
                scrollView.scrollWheel(with: event)
            }
            return true
        }

        /// The innermost scroll view under the pointer that can scroll sideways (its document is wider than its clip
        /// view): over a sidebar page's list, the sidebar's pages; over a card, the strip.
        /// None can (a one-tab strip, one sidebar page): the innermost still takes it, so a terminal never does.
        private static func scrollView(_ event: NSEvent) -> NSScrollView? {
            let innermost = event.window?.contentView?.hitTest(event.locationInWindow)?.enclosingScrollView
            var view = innermost
            while let scrollView = view,
                  (scrollView.documentView?.frame.width ?? 0) <= scrollView.contentView.bounds.width + 0.5
            {
                view = scrollView.enclosingScrollView
            }
            return view ?? innermost
        }
    }

    /// Marks the strip's scroll view for the router, with the page turn for wheels.
    private struct StripAnchor: NSViewRepresentable {
        let page: Page

        func makeNSView(context _: Context) -> Anchor {
            Anchor(step: page.step)
        }

        func updateNSView(_ view: Anchor, context _: Context) {
            view.step = page.step
        }

        final class Anchor: NSView {
            var step: (Int) -> Void

            init(step: @escaping (Int) -> Void) {
                self.step = step
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if window != nil {
                    SwipeRouter.strips.add(self)
                }
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    }

    /// herdr's split tree: each split divides its rectangle by the ratio, minus the gap, which is the split's divider.
    /// Both children get an exact size, so no card's content can push its neighbor out of the page. A zoomed card
    /// (design D11) fills the page: each split above it stacks its sides, the zoomed side at full size, the other
    /// hidden at its own size. The same views stay, so no terminal view changes host and only the zoomed one resizes.
    private struct SplitLayout: View {
        let node: SplitNode
        let page: Page
        let tabID: String
        /// From the root, `false` = first child, as `layout.set_split_ratio` takes it.
        var path: [Bool] = []
        /// The size without zoom, for a split above the zoomed card: it fills the page, its parts keep their size.
        var natural: CGSize?
        /// The app's ratio while its divider is dragged or sent, until herdr's snapshot shows its own.
        @State private var held: Double?

        var body: some View {
            switch node {
            case let .leaf(paneID):
                PaneCard(id: paneID, page: page)
            case let .split(direction, ratio, first, second):
                GeometryReader { geometry in
                    let right = direction == .right
                    let base = natural ?? geometry.size
                    let total = max(0, (right ? base.width : base.height) - gap)
                    // A NaN or out-of-range ratio from herdr must not break the layout.
                    let shown = held ?? (ratio.isNaN ? 0.5 : min(max(ratio, 0), 1))
                    let size = total * shown
                    let sizes = right
                        ? (CGSize(width: size, height: base.height), CGSize(width: total - size, height: base.height))
                        : (CGSize(width: base.width, height: size), CGSize(width: base.width, height: total - size))
                    let zoomed = page.zoomedPaneID.map { (first.contains($0), second.contains($0)) } ?? (false, false)
                    let stack = zoomed.0 || zoomed.1 ? AnyLayout(ZStackLayout())
                        : right ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                    stack {
                        side(first, sizes.0, step: false, zoomed: zoomed, area: geometry.size)
                        if !zoomed.0, !zoomed.1 {
                            let names = [first, second].map { page.store.pane($0.paneIDs[0])?.cardTitle ?? "terminal" }
                            let key = path.isEmpty ? "root" : path.map { $0 ? "1" : "0" }.joined()
                            SplitDivider(right: right, total: total, ratio: shown, held: $held,
                                         label: "Divider between \(names[0]) and \(names[1])",
                                         id: "divider.\(tabID).\(key)",
                                         send: { send($0, herdr: ratio) })
                        }
                        side(second, sizes.1, step: true, zoomed: zoomed, area: geometry.size)
                    }
                }
                .onChange(of: ratio) { held = nil }
            }
        }

        /// One side of a split: its own size, the whole rectangle when it holds the zoomed card, or hidden under it.
        /// `zoomed`: whether the first and the second side hold the zoomed card.
        private func side(_ node: SplitNode, _ size: CGSize, step: Bool, zoomed sides: (Bool, Bool),
                          area: CGSize) -> some View
        {
            let zoomed = step ? sides.1 : sides.0, away = step ? sides.0 : sides.1
            return SplitLayout(node: node, page: page, tabID: tabID, path: path + [step], natural: zoomed ? size : nil)
                .frame(width: zoomed ? area.width : size.width, height: zoomed ? area.height : size.height)
                // Under the zoomed side (zIndex), which covers it, so its terminal views get no clicks.
                .opacity(away ? 0 : 1)
                .zIndex(away ? 0 : 1)
                .transformEnvironment(\.zoomedAway) { $0 = $0 || away }
        }

        /// The divider's ratio to herdr (D42). Held until the snapshot shows it; dropped when herdr refused it, or
        /// when herdr already has it (no snapshot change would drop it then).
        private func send(_ value: Double, herdr ratio: Double) {
            guard abs(value - ratio) > 0.0005 else {
                held = nil
                return
            }
            Task {
                if await !page.store.setRatio(tab: tabID, path: path, ratio: value) {
                    held = nil
                }
            }
        }
    }

    /// A split's 8 pt gap: a 16 pt hit area with the resize pointer, a grip on hover (gorex's 36 × 3 pt, muted at
    /// 0.6), a drag that moves the split live and sends on release, a double-click for 0.5, and an adjustable
    /// accessibility element (5 % steps).
    private struct SplitDivider: View {
        let right: Bool
        /// The split's length without the gap.
        let total: CGFloat
        let ratio: Double
        @Binding var held: Double?
        let label: String
        let id: String
        let send: (Double) -> Void
        @State private var hovering = false
        /// The ratio when the drag began.
        @State private var start: Double?

        var body: some View {
            Color.clear
                .frame(width: right ? gap : nil, height: right ? nil : gap)
                .overlay {
                    Capsule().fill(.secondary.opacity(0.6))
                        .frame(width: right ? 3 : 36, height: right ? 36 : 3)
                        .opacity(hovering || start != nil ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: hovering || start != nil)
                }
                .overlay {
                    Color.clear.contentShape(.rect)
                        .frame(width: right ? 16 : nil, height: right ? nil : 16)
                        .pointerStyle(right ? .columnResize : .rowResize)
                        .onHover { hovering = $0 }
                        // Global: the divider moves under the pointer, so its own space would move too.
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
                            let from = start ?? ratio
                            start = from
                            let moved = right ? drag.translation.width : drag.translation.height
                            held = min(max(from + moved / max(total, 1), 0.1), 0.9)
                        }.onEnded { _ in
                            start = nil
                            if let held {
                                send(held)
                            }
                        })
                        .onTapGesture(count: 2) { set(0.5) }
                        .accessibilityElement()
                        .accessibilityLabel(label)
                        .accessibilityValue("\(Int((ratio * 100).rounded()))%")
                        .accessibilityIdentifier(id)
                        .accessibilityAdjustableAction { direction in
                            set(min(max(ratio + (direction == .increment ? 0.05 : -0.05), 0.1), 0.9))
                        }
                }
                // Over both sides' edges: its hit area reaches 4 pt into each card.
                .zIndex(2)
        }

        private func set(_ value: Double) {
            held = value
            send(value)
        }
    }

    extension EnvironmentValues {
        /// The card is under a zoomed card: hidden, but there, so its terminal keeps its size.
        @Entry var zoomedAway = false
    }

    private extension SplitNode {
        func contains(_ paneID: String) -> Bool {
            switch self {
            case let .leaf(id): id == paneID
            case let .split(_, _, first, second): first.contains(paneID) || second.contains(paneID)
            }
        }
    }
#endif
