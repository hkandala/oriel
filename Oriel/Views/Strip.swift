#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// One full-size page per tab of the workspace, paged sideways by a swipe (`Paging`, which selects the tab it
    /// lands on) or a wheel. A new selection (a click, a key, a new or closed tab) shows its page at once: only a swipe
    /// or a mouse's wheel slides (phase 24).
    struct Strip: View {
        let workspace: HostStore.Workspace
        let page: Page
        /// The page in view, as the scroll view has it.
        @State private var position = ScrollPosition(idType: String.self)
        @State private var paging = Paging()
        /// e2e (`-recordStrip YES`): the scroll updates that left the strip between two pages, that is, a slide.
        @State private var between = 0
        private static let record = UserDefaults.standard.bool(forKey: "recordStrip")
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // Pages the reader's size, not `containerRelativeFrame`'s: on a new strip's first layout that took the
            // window's width, so the first offset (`defaultScrollAnchor`) was off by a fraction of a page, and the
            // scroll geometry reported last could be that one: the tab capsule rested between two tabs (phase 31).
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(workspace.tabs) { tab in
                            Group {
                                if let tree = tab.tree {
                                    // Inside the scroll view, which clips: room for the cards' outer stroke and shadow.
                                    let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                                    SplitLayout(tree: tree, zoomed: zoomed, page: page, tabID: tab.id)
                                        .padding([.horizontal, .bottom], gap)
                                        .padding(.top, 4)
                                } else {
                                    Text("No layout for this tab").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("page.\(tab.id)")
                        }
                    }
                    .scrollTargetLayout()
                    .background(ScrollAnchor(step: turn, drag: drag, lift: lift))
                }
            }
            // No `.paging`: it snapped the swipe's first move to the next page (phase 31, CI).
            // A new strip (a workspace or session shown, the overview closed) is laid out on the selected tab's page
            // from its first frame: the scroll below finds a lazy page only once it is laid out, so the strip drew its
            // first page for a frame and then jumped (phase 29).
            .defaultScrollAnchor(start, for: .initialOffset)
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
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { paging.laid($1) })
            .testValue("strip.between", "Strip Between Pages", "\(between)", shown: Self.record)
            .onScrollPhaseChange { _, phase in
                // Not a tab that closed meanwhile.
                if phase == .idle, let shown = position.viewID(type: String.self),
                   workspace.tabs.contains(where: { $0.id == shown })
                {
                    page.selectedTabIDs[workspace.id] = shown
                }
            }
            .onChange(of: page.selectedTabIDs[workspace.id], initial: true) {
                guard let target = page.selectedTabIDs[workspace.id],
                      position.viewID(type: String.self) != target else { return }
                withTransaction(\.animation, nil) { position.scrollTo(id: target, anchor: .leading) }
                // A page that lays out in this same update (a new tab's, or herdr's tab taking its stand-in's place)
                // can miss the scroll: again once it has.
                Task { position.scrollTo(id: target, anchor: .leading) }
            }
        }

        /// The selected tab's page as a point of the pages' width.
        private var start: UnitPoint {
            let count = Double(max(workspace.tabs.count - 1, 1))
            return UnitPoint(x: Double(page.selectedIndex(in: workspace)) / count, y: 0)
        }

        /// A swipe's moves and lift (`Paging`); the tab it lands on is selected as its page arrives, unless it closed.
        private func drag(_ delta: Double, _: Bool) {
            paging.drag(delta, count: workspace.tabs.count, $position)
        }

        private func lift(_ speed: Double) {
            paging.lift(speed, ids: workspace.tabs.map(\.id), $position, reduceMotion: reduceMotion) { tab in
                if page.store.workspace(of: tab) != nil {
                    page.selectedTabIDs[workspace.id] = tab
                }
            }
        }

        /// A mouse's sideways wheel turns a page with Rex's spring. The scroll is there before the
        /// selection's change runs, so that change does not scroll again.
        private func turn(_ offset: Int) {
            page.step(offset)
            if let target = page.selectedTabIDs[workspace.id] {
                withAnimation(reduceMotion && !Animation.forceMotion ? nil : .tab) {
                    position.scrollTo(id: target, anchor: .leading)
                }
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
        let page: Page
        let tabID: String
        /// The cards in their place, in the tree's order, with the id their view goes by: one new since the page first
        /// drew starts beside its place and slides in. Not a transition: `.move` and `.offset` transitions moved
        /// nothing here (CI recordings), only their fade ran.
        @State private var placed: [(id: String, view: String)]?
        /// The app's ratio of a split (by path) while its divider is dragged or sent, until herdr's snapshot shows its
        /// own.
        @State private var held: [[Bool]: Double] = [:]
        /// e2e (`-recordMotion YES`): the cards that came into the page and went from it.
        @State private var cards = (came: 0, went: 0)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// A split, a close, a swap or a zoom; the terminals keep their size until it ends (`TerminalHost`). A third
        /// shorter than phase 25's 0.2 s, which the user found slow (phase 27).
        private var motion: Animation? {
            reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.13)
        }

        var body: some View {
            GeometryReader { geometry in
                let area = CGRect(origin: .zero, size: geometry.size)
                let parts = Parts(tree, in: area, held: held)
                let views = views(parts.cards.map(\.id))
                ZStack(alignment: .topLeading) {
                    ForEach(parts.cards.map { (view: views[$0.id] ?? $0.id, card: $0) }, id: \.view) { _, card in
                        let away = zoomed != nil && zoomed != card.id
                        // A new card slides in from its side as the others make room, its edge on theirs.
                        let entering = placed != nil && views[card.id] == nil
                        let rect = zoomed == card.id ? area : entering ? card.start : card.rect
                        PaneCard(id: card.id, page: page, away: away)
                            .place(rect)
                            // Under the zoomed card, which covers it, so its terminal views get no clicks.
                            .opacity(away ? 0 : 1)
                            // A new card fades in over half its slide: a longer fade made the panes feel slow (user,
                            // phase 29).
                            .animation(motion.map { _ in .easeOut(duration: 0.06) }) { $0.opacity(entering ? 0 : 1) }
                            .zIndex(away ? 0 : 1)
                            .allowsHitTesting(!away)
                            // A closed card fades as the others grow. A new one fades in with its slide (`entering`).
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                            .onAppear {
                                if TerminalHost.Host.record {
                                    cards.came += 1
                                }
                            }
                            .onDisappear {
                                if TerminalHost.Host.record {
                                    cards.went += 1
                                }
                            }
                    }
                    ForEach(parts.dividers, id: \.id) { divider in
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
            .testValue("cards.\(tabID)", "Cards", "\(cards.came) \(cards.went)", shown: TerminalHost.Host.record)
            .animation(motion, value: tree)
            .animation(motion, value: zoomed)
            .onChange(of: tree, initial: true) {
                let views = views(tree.paneIDs)
                withAnimation(motion) {
                    placed = tree.paneIDs.map { ($0, views[$0] ?? $0) }
                }
            }
        }

        /// The view id of each of these cards already in place. herdr's panes that took splits' stand-ins (`Ahead`)
        /// keep the stand-ins' views, in order, so each new card comes once, where it ends up: a quick ⌘D's stand-ins
        /// are replaced in one snapshot, and herdr's panes as new views slid in beside them as they went (phase 30).
        private func views(_ ids: [String]) -> [String: String] {
            guard let placed else { return [:] }
            // Not `uniqueKeysWithValues`: a pane twice in herdr's tree must not crash the app.
            var views = Dictionary(placed.filter { ids.contains($0.id) }, uniquingKeysWith: { first, _ in first })
            let gone = placed.filter { Ahead.isStandIn($0.id) && !ids.contains($0.id) }
            for (new, old) in zip(ids.filter { views[$0] == nil }, gone) {
                views[new] = old.view
            }
            return views
        }
    }

    /// Where each card and divider of the tree goes: each split divides its rectangle by its ratio, less the 8 pt gap,
    /// which is its divider. Both sides get an exact size, so no card's content can push its neighbor out of the page.
    struct Parts {
        struct Card {
            let id: String
            let rect: CGRect
            /// Where it slides in from: beside its place, on its side of its split.
            let start: CGRect
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
            add(tree, area, path: [], side: CGVector(dx: 1, dy: 0), held: held)
        }

        /// `side`: the card's side of its split, as a unit step (right, left, down or up).
        private mutating func add(_ node: SplitNode, _ rect: CGRect, path: [Bool], side: CGVector,
                                  held: [[Bool]: Double])
        {
            switch node {
            case let .leaf(id):
                let start = rect.offsetBy(dx: side.dx * (rect.width + gap), dy: side.dy * (rect.height + gap))
                cards.append(Card(id: id, rect: rect, start: start))
            case let .split(direction, ratio, first, second):
                let right = direction == .right, from: CGRectEdge = right ? .minXEdge : .minYEdge
                let total = max(0, (right ? rect.width : rect.height) - gap)
                let herdr = ratio.isNaN ? 0.5 : min(max(ratio, 0), 1)
                let (one, rest) = rect.divided(atDistance: total * (held[path] ?? herdr), from: from)
                let (line, two) = rest.divided(atDistance: gap, from: from)
                add(first, one, path: path + [false], side: right ? CGVector(dx: -1, dy: 0) : CGVector(dx: 0, dy: -1),
                    held: held)
                dividers.append(Divider(path: path, right: right, rect: line, total: total, ratio: herdr,
                                        beside: [first.paneIDs.last, second.paneIDs.first]))
                add(second, two, path: path + [true], side: right ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1),
                    held: held)
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
        /// At this rectangle of the page, by layout (`position`), not `.offset`: a layout change animates every view in
        /// it, the terminal's too. (Padding gave a card sliding in from the left a size below zero, and it came in
        /// header high.)
        func place(_ rect: CGRect) -> some View {
            frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
#endif
