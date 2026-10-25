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
                                // Layout motion (0.2 s): a split, a close, a swap, a zoom. The terminals keep their
                                // size until it ends (`TerminalHost`).
                                let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                                let motion = reduceMotion && !Animation.forceMotion ? nil : Animation
                                    .easeOut(duration: 0.2)
                                SplitLayout(tree: tree, zoomed: zoomed, motion: motion, page: page, tabID: tab.id)
                                    .animation(motion, value: tree)
                                    .animation(motion, value: zoomed)
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
                // Not a tab that closed meanwhile.
                if phase == .idle, let shown = position.viewID(type: String.self),
                   workspace.tabs.contains(where: { $0.id == shown })
                {
                    page.selectedTabIDs[workspace.id] = shown
                }
            }
            // The tab marker follows the scroll.
            .onChange(of: page.selectedTabIDs[workspace.id], initial: true) {
                guard let target = page.selectedTabIDs[workspace.id],
                      position.viewID(type: String.self) != target else { return }
                withTransaction(\.animation, nil) { position.scrollTo(id: target, anchor: .leading) }
                // A page that lays out in this same update (the strip's first, a new tab's) can miss the scroll (a new
                // workspace came up blank): again once it has.
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

    /// herdr's split tree, drawn flat: each card and divider is placed in the page by its rectangle, and keeps its view
    /// (by pane id, or the split's path) whatever the tree does. So a split, a close, a swap or a zoom moves and sizes
    /// the same cards: their frames animate, and no terminal view changes host. (Nested stacks, one per split, made a
    /// new card for a pane whose leaf became a split or whose sibling closed, so it jumped to its new size.)
    private struct SplitLayout: View {
        let tree: SplitNode
        /// The tab's zoomed card (D11): it fills the page; the others stay at their size, hidden under it, so their
        /// terminals keep their size.
        let zoomed: String?
        let motion: Animation?
        let page: Page
        let tabID: String
        /// The cards in their place: one new since the page first drew starts beside its place and slides in. Not a
        /// transition: `.move` and `.offset` transitions moved nothing here (CI recordings), only their fade ran.
        @State private var placed: Set<String>?
        /// The app's ratio of a split (by path) while its divider is dragged or sent, until herdr's snapshot shows its
        /// own.
        @State private var held: [[Bool]: Double] = [:]

        var body: some View {
            GeometryReader { geometry in
                let area = CGRect(origin: .zero, size: geometry.size)
                let parts = Parts(tree, in: area, held: held)
                ZStack(alignment: .topLeading) {
                    ForEach(parts.cards, id: \.id) { card in
                        let away = zoomed != nil && zoomed != card.id
                        // A new card slides in from its side as the others make room, its edge on theirs.
                        let entering = placed.map { !$0.contains(card.id) } ?? false
                        let rect = zoomed == card.id ? area : entering ? card.rect.offsetBy(dx: card.from.width,
                                                                                            dy: card.from.height)
                            : card.rect
                        PaneCard(id: card.id, page: page, away: away)
                            .place(rect)
                            // Under the zoomed card, which covers it, so its terminal views get no clicks.
                            .opacity(away || entering ? 0 : 1)
                            .zIndex(away ? 0 : 1)
                            .allowsHitTesting(!away)
                            // A closed card fades as the others grow (a scale would leave its terminal view at full
                            // size).
                            .transition(.opacity)
                    }
                    ForEach(parts.dividers, id: \.id) { divider in
                        // The panes beside the divider.
                        let names = divider.beside.map { $0.flatMap(page.store.pane)?.cardTitle ?? "terminal" }
                        SplitDivider(divider: divider, held: $held[divider.path], page: page, tabID: tabID,
                                     label: "Divider between \(names[0]) and \(names[1])")
                            .place(divider.rect)
                            .opacity(zoomed == nil ? 1 : 0)
                            .allowsHitTesting(zoomed == nil)
                            .accessibilityHidden(zoomed != nil)
                            // Over both sides' edges: its hit area reaches 4 pt into each card.
                            .zIndex(2)
                    }
                }
            }
            .onAppear { placed = Set(tree.paneIDs) }
            .onChange(of: tree) { old, new in
                // herdr's pane in a split's stand-in (`Ahead`) takes its place without a second slide.
                withAnimation(old.paneIDs.contains(where: Ahead.isStandIn) ? nil : motion) {
                    placed = Set(new.paneIDs)
                }
            }
        }
    }

    /// Where each card and divider of the tree goes: each split divides its rectangle by its ratio, less the 8 pt gap,
    /// which is its divider. Both sides get an exact size, so no card's content can push its neighbor out of the page.
    private struct Parts {
        struct Card {
            let id: String
            let rect: CGRect
            /// Its side of its split, where it slides in from.
            let edge: Edge

            /// Where it slides in from: beside its place, on its side.
            var from: CGSize {
                switch edge {
                case .leading: CGSize(width: -rect.width - gap, height: 0)
                case .trailing: CGSize(width: rect.width + gap, height: 0)
                case .top: CGSize(width: 0, height: -rect.height - gap)
                case .bottom: CGSize(width: 0, height: rect.height + gap)
                }
            }
        }

        struct Divider {
            /// From the root, `false` = first child, as `layout.set_split_ratio` takes it.
            let path: [Bool]
            let right: Bool
            let rect: CGRect
            /// The split's length without the gap.
            let total: CGFloat
            /// herdr's, kept in 0–1 (a NaN or out-of-range ratio from herdr must not break the layout).
            let ratio: Double
            /// The last pane of the first side and the first of the second.
            let beside: [String?]

            /// The path in `0` and `1` digits, `root` for the root split.
            var id: String {
                path.isEmpty ? "root" : path.map { $0 ? "1" : "0" }.joined()
            }
        }

        private(set) var cards: [Card] = []
        private(set) var dividers: [Divider] = []

        init(_ tree: SplitNode, in area: CGRect, held: [[Bool]: Double]) {
            add(tree, area, path: [], edge: .trailing, held: held)
        }

        private mutating func add(_ node: SplitNode, _ rect: CGRect, path: [Bool], edge: Edge,
                                  held: [[Bool]: Double])
        {
            switch node {
            case let .leaf(id):
                cards.append(Card(id: id, rect: rect, edge: edge))
            case let .split(direction, ratio, first, second):
                let right = direction == .right, from: CGRectEdge = right ? .minXEdge : .minYEdge
                let total = max(0, (right ? rect.width : rect.height) - gap)
                let herdr = ratio.isNaN ? 0.5 : min(max(ratio, 0), 1)
                let (one, rest) = rect.divided(atDistance: total * (held[path] ?? herdr), from: from)
                let (line, two) = rest.divided(atDistance: gap, from: from)
                add(first, one, path: path + [false], edge: right ? .leading : .top, held: held)
                dividers.append(Divider(path: path, right: right, rect: line, total: total, ratio: herdr,
                                        beside: [first.paneIDs.last, second.paneIDs.first]))
                add(second, two, path: path + [true], edge: right ? .trailing : .bottom, held: held)
            }
        }
    }

    /// A split's 8 pt gap: a 16 pt hit area with the resize pointer, a grip on hover (gorex's 36 × 3 pt, muted at
    /// 0.6), a drag that moves the split live and sends on release, a double-click for 0.5, and an adjustable
    /// accessibility element (5 % steps).
    private struct SplitDivider: View {
        let divider: Parts.Divider
        /// The app's ratio while dragged or sent, until herdr's snapshot shows its own.
        @Binding var held: Double?
        let page: Page
        let tabID: String
        let label: String
        @State private var hovering = false
        @Environment(\.look) private var look
        /// The ratio when the drag began.
        @State private var start: Double?
        /// The last change asked for, and the last one sent: only the latest goes, and `held` stays until its snapshot.
        @State private var asked = 0
        @State private var sent = 0

        private var right: Bool {
            divider.right
        }

        private var ratio: Double {
            held ?? divider.ratio
        }

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
                        .accessibilityIdentifier("divider.\(tabID).\(divider.id)")
                        .accessibilityAdjustableAction { direction in
                            send(hold(ratio + (direction == .increment ? 0.05 : -0.05)))
                        }
                }
                .onChange(of: divider.ratio) {
                    if sent == asked {
                        held = nil
                    }
                }
                // Its split closed: a later split at the same path must not take its ratio.
                .onDisappear { held = nil }
        }

        /// The ratio to herdr (D10). Held until the snapshot shows it; dropped when herdr refused it, or when herdr
        /// already has it (no snapshot change would drop it then).
        private func send(_ value: Double) {
            // herdr has it already, and no other change is on its way.
            guard sent != asked || abs(value - divider.ratio) > 0.0005 else {
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
                let done = await page.store.setRatio(tab: tabID, path: divider.path, ratio: value)
                sent = change
                if !done {
                    held = nil
                }
            }
        }

        /// The ratio the drag points at, from the ratio when it began.
        private func dragged(_ drag: DragGesture.Value) -> Double {
            let from = start ?? ratio
            start = from
            return from + (right ? drag.translation.width : drag.translation.height) / max(divider.total, 1)
        }

        /// In herdr's 0.1–0.9, so the view shows what herdr keeps.
        @discardableResult
        private func hold(_ value: Double) -> Double {
            let clamped = min(max(value, 0.1), 0.9)
            held = clamped
            return clamped
        }
    }

    private extension View {
        /// At this rectangle of the page, by layout (padding), not `.offset`: a layout change animates every view in
        /// it, the terminal's too.
        func place(_ rect: CGRect) -> some View {
            frame(width: rect.width, height: rect.height)
                .padding(.leading, rect.minX)
                .padding(.top, rect.minY)
        }
    }
#endif
