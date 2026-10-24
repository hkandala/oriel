#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// One full-size page per tab of the workspace, paged sideways. The selection follows the page in view when the
    /// scroll stops. A new selection (a click, a key, a new or closed tab) shows its page at once: only a scroll
    /// gesture or a mouse's wheel slides (phase 24).
    struct Strip: View {
        let workspace: HostStore.Workspace
        let page: Page
        /// The page in view, as the scroll view has it.
        @State private var position = ScrollPosition(idType: String.self)
        /// e2e (`-recordStrip YES`): the scroll updates that left the strip between two pages, that is, a slide.
        @State private var between = 0
        private static let record = UserDefaults.standard.bool(forKey: "recordStrip")
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        Group {
                            if let tree = tab.tree {
                                // Inside the scroll view, which clips: room for the cards' outer stroke and shadow.
                                // Layout motion (0.2 s); the terminals keep their size until it ends (`TerminalHost`).
                                SplitLayout(node: tree, page: page, tabID: tab.id)
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
                .background(StripAnchor(step: turn))
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
                if Self.record, $1 != $1.rounded() {
                    between += 1
                }
            }
            .testValue("strip.between", "Strip Between Pages", "\(between)", shown: Self.record)
            .onScrollPhaseChange { _, phase in
                // Not a page of the workspace that was shown before a switch.
                if phase == .idle, let shown = position.viewID(type: String.self),
                   workspace.tabs.contains(where: { $0.id == shown })
                {
                    page.selectedTabIDs[workspace.id] = shown
                }
            }
            // One strip for every workspace. The tab marker follows the scroll.
            .onChange(of: [workspace.id, page.selectedTabIDs[workspace.id]], initial: true) {
                guard let target = page.selectedTabIDs[workspace.id],
                      position.viewID(type: String.self) != target else { return }
                withTransaction(\.animation, nil) { position.scrollTo(id: target, anchor: .leading) }
                // A page that lays out in this same update (another workspace's, a new tab's) can miss the scroll (a
                // new workspace came up blank): again once it has.
                Task { position.scrollTo(id: target, anchor: .leading) }
            }
        }

        /// A mouse's sideways wheel turns a page with Rex's spring, as a swipe would. The scroll is there before the
        /// selection's change runs, so that change does not scroll again.
        private func turn(_ offset: Int) {
            page.step(offset)
            if let target = page.selectedTabIDs[workspace.id] {
                withAnimation(reduceMotion ? nil : .tab) { position.scrollTo(id: target, anchor: .leading) }
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
        /// The last divider change asked for, and the last one sent: only the latest goes, and `held` stays until its
        /// snapshot.
        @State private var asked = 0
        @State private var sent = 0

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
                    let zoomed = page.zoomedPaneID.map { (first.paneIDs.contains($0), second.paneIDs.contains($0)) }
                        ?? (false, false)
                    let stack = zoomed.0 || zoomed.1 ? AnyLayout(ZStackLayout())
                        : right ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                    stack {
                        side(first, sizes.0, step: false, zoomed: zoomed, area: geometry.size)
                        if !zoomed.0, !zoomed.1 {
                            // The panes beside the divider.
                            let names = [first.paneIDs.last, second.paneIDs.first]
                                .map { $0.flatMap(page.store.pane)?.cardTitle ?? "terminal" }
                            let key = path.isEmpty ? "root" : path.map { $0 ? "1" : "0" }.joined()
                            SplitDivider(right: right, total: total, ratio: shown, held: $held,
                                         label: "Divider between \(names[0]) and \(names[1])",
                                         id: "divider.\(tabID).\(key)",
                                         send: { send($0, herdr: ratio) })
                        }
                        side(second, sizes.1, step: true, zoomed: zoomed, area: geometry.size)
                    }
                }
                .onChange(of: ratio) {
                    if sent == asked {
                        held = nil
                    }
                }
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
                .allowsHitTesting(!away)
                .transformEnvironment(\.zoomedAway) { $0 = $0 || away }
        }

        /// The divider's ratio to herdr (D10). Held until the snapshot shows it; dropped when herdr refused it, or
        /// when herdr already has it (no snapshot change would drop it then).
        private func send(_ value: Double, herdr ratio: Double) {
            // herdr has it already, and no other change is on its way.
            guard sent != asked || abs(value - ratio) > 0.0005 else {
                held = nil
                return
            }
            asked += 1
            let change = asked
            Task {
                // After a write in flight (a quick second change), not refused as busy.
                while page.store.writing {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                // A newer change replaced it while it waited.
                guard change == asked else { return }
                let done = await page.store.setRatio(tab: tabID, path: path, ratio: value)
                sent = change
                if !done {
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
        @Environment(\.look) private var look
        /// The ratio when the drag began.
        @State private var start: Double?

        var body: some View {
            Color.clear
                .frame(width: right ? gap : nil, height: right ? nil : gap)
                .overlay {
                    Capsule().fill(look.grip)
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
                            hold(dragged(drag))
                        }.onEnded { drag in
                            // From the gesture: a snapshot during the drag may have dropped `held`.
                            send(hold(dragged(drag)))
                            start = nil
                        })
                        .onTapGesture(count: 2) { send(hold(0.5)) }
                        .accessibilityElement()
                        .accessibilityLabel(label)
                        // As the cards: a plain element shows XCUITest no value.
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityValue("\(Int((ratio * 100).rounded()))%")
                        .accessibilityIdentifier(id)
                        .accessibilityAdjustableAction { direction in
                            send(hold(ratio + (direction == .increment ? 0.05 : -0.05)))
                        }
                }
                // Over both sides' edges: its hit area reaches 4 pt into each card.
                .zIndex(2)
        }

        /// The ratio the drag points at, from the ratio when it began.
        private func dragged(_ drag: DragGesture.Value) -> Double {
            let from = start ?? ratio
            start = from
            return from + (right ? drag.translation.width : drag.translation.height) / max(total, 1)
        }

        /// In herdr's 0.1–0.9, so the view shows what herdr keeps.
        @discardableResult
        private func hold(_ value: Double) -> Double {
            let clamped = min(max(value, 0.1), 0.9)
            held = clamped
            return clamped
        }
    }

    extension EnvironmentValues {
        /// The card is under a zoomed card: hidden, but there, so its terminal keeps its size.
        @Entry var zoomedAway = false
    }
#endif
