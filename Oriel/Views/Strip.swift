import HerdrKit
import SwiftUI

/// One full-size page per tab of the workspace, paged sideways by a swipe (`Paging`, which selects the tab it
/// lands on) or a wheel. A new selection (a click, a key, a new or closed tab) shows its page at once: only a swipe
/// or a mouse's wheel slides.
struct Strip: View {
    let workspace: HostStore.Workspace
    let pages: WindowPages
    let page: Page
    /// The page in view, as the scroll view has it.
    @State private var position = ScrollPosition(idType: String.self)
    @State private var paging = Paging()
    /// e2e (`-recordStrip YES`): the scroll updates that left the strip between two pages, that is, a slide.
    @State private var between = 0
    /// The tabs' order changed while the strip moved: it follows the selected tab when it comes to rest (`follow`).
    @State private var reordered = false
    /// Counts the times the selected tab moved: each makes the scroll view anew on its page (`follow`).
    @State private var moves = 0
    private static let record = UserDefaults.standard.bool(forKey: "recordStrip")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Pages the reader's size, not `containerRelativeFrame`'s: on a new strip's first layout that took the
        // window's width, so the first offset (`defaultScrollAnchor`) was off by a fraction of a page, and the
        // scroll geometry reported last could be that one: the tab capsule rested between two tabs.
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        Group {
                            if let tree = tab.tree {
                                let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                                SplitLayout(tree: tree, zoomed: zoomed, page: page, tabID: tab.id)
                                    .padding(Self.inset)
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
            .id(moves)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { pages.terminals.stripSize = $0 }
        // No `.paging`: it snapped the swipe's first move to the next page (on CI).
        // A new strip (a workspace or session shown, the overview closed) is laid out on the selected tab's page
        // from its first frame: the scroll below finds a lazy page only once it is laid out, so the strip drew its
        // first page for a frame and then jumped.
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
        // Web cards wait for the strip to rest (`Page.cards`), also one that goes mid-scroll.
        .onDisappear { moving(false) }
        .onScrollPhaseChange { _, phase in
            let follows = reordered
            moving(phase != .idle)
            // Not a tab that closed meanwhile, and not over a selection whose tab moved meanwhile: the strip went to
            // it.
            if phase == .idle, !follows, let shown = position.viewID(type: String.self),
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
        .onChange(of: workspace.tabs.map(\.id)) { old, new in
            let selected = page.selectedTabIDs[workspace.id]
            // A move, not a tab made or closed (the selection and the stack take those).
            if Set(old) == Set(new),
               old.firstIndex(where: { $0 == selected }) != new.firstIndex(where: { $0 == selected })
            {
                follow()
            }
        }
    }

    /// The selected tab moved (an open's new tab is made last, then moved beside its card; a drag): the strip kept its
    /// offset and showed another tab's page than the selected one, and a scroll to the selected tab's
    /// place found no page there (the lazy stack made none for the tab that came to it, CI): item 28. The scroll view
    /// is
    /// made anew, laid out on the selected tab's page from its first frame (`defaultScrollAnchor`), as for a workspace
    /// shown; while the strip moves, once it rests.
    private func follow() {
        guard !page.stripMoving else {
            reordered = true
            return
        }
        reordered = false
        position = ScrollPosition(idType: String.self)
        moves += 1
        if let target = page.selectedTabIDs[workspace.id] {
            Task { position.scrollTo(id: target, anchor: .leading) }
        }
    }

    /// A page's cards inside its page: room for the cards' outer stroke and shadow, the scroll view clips.
    static let inset = EdgeInsets(top: 4, leading: gap, bottom: gap, trailing: gap)

    /// The cards' area in a page of this size.
    static func area(_ size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width - inset.leading - inset.trailing,
               height: size.height - inset.top - inset.bottom)
    }

    /// The selected tab's page as a point of the pages' width.
    private var start: UnitPoint {
        let count = Double(max(workspace.tabs.count - 1, 1))
        return UnitPoint(x: Double(page.selectedIndex(in: workspace)) / count, y: 0)
    }

    /// A swipe's moves and lift (`Paging`); the tab it lands on is selected as its page arrives, unless it closed.
    /// Not under a panel opened mid-swipe (the palette, Open Session): back to the selected tab's page. A swipe
    /// that starts under one never comes here (the panel's backdrop takes the hit test).
    /// The fingers move the strip without an animation, so its scroll phase stays idle: they say it moves.
    private func drag(_ delta: Double, _: Bool) {
        guard !pages.panelOpen else { return }
        moving(true)
        paging.drag(delta, count: workspace.tabs.count, $position)
    }

    private func lift(_ speed: Double) {
        guard !pages.panelOpen else {
            moving(false)
            return position.scrollTo(id: workspace.tabs[page.selectedIndex(in: workspace)].id, anchor: .leading)
        }
        // A slide reports its own phase; a jump (Reduce Motion, or on the page already) lands at once.
        paging.lift(speed, ids: workspace.tabs.map(\.id), $position, reduceMotion: reduceMotion) { tab in
            moving(false)
            if page.store.workspace(of: tab) != nil {
                page.selectedTabIDs[workspace.id] = tab
            }
        }
    }

    /// Only a change: every card reads it.
    private func moving(_ moving: Bool) {
        if page.stripMoving != moving {
            page.stripMoving = moving
        }
        if !moving, reordered {
            follow()
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

    /// A split, a close, a swap or a zoom; the terminals keep their size until it ends (`TerminalHost`). 0.2 s felt
    /// slow.
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
                        // A new card fades in over half its slide: a longer fade made the panes feel slow.
                        .animation(motion.map { _ in .easeOut(duration: 0.06) }) { $0.opacity(entering ? 0 : 1) }
                        .zIndex(away ? 0 : 1)
                        .allowsHitTesting(!away)
                        // A closed card fades as the others grow. A new one fades in with its slide (`entering`).
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        .onAppear {
                            if SettlingHost.record {
                                cards.came += 1
                            }
                        }
                        .onDisappear {
                            if SettlingHost.record {
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
        .testValue("cards.\(tabID)", "Cards", "\(cards.came) \(cards.went)", shown: SettlingHost.record)
        .animation(motion, value: tree)
        .animation(motion, value: zoomed)
        .onChange(of: tree, initial: true) {
            let views = views(tree.paneIDs)
            withAnimation(motion) {
                placed = tree.paneIDs.map { ($0, views[$0] ?? $0) }
            }
        }
    }

    /// The view id of each of these cards already in place. herdr's panes that took splits' stand-ins (`Ahead`) keep
    /// their views, in order, so each new card comes once, where it ends up; a replaced pane's new pane keeps its card,
    /// in place (no slide in, no fade out).
    private func views(_ ids: [String]) -> [String: String] {
        guard let placed else { return [:] }
        // Not `uniqueKeysWithValues`: a pane twice in herdr's tree must not crash the app.
        var views = Dictionary(placed.filter { ids.contains($0.id) }, uniquingKeysWith: { first, _ in first })
        for (new, old) in page.store.ahead.cards where ids.contains(new) {
            views[new] = placed.first { $0.id == old }?.view ?? views[new]
        }
        let gone = placed.filter { Ahead.isStandIn($0.id) && !ids.contains($0.id) }
        for (new, old) in zip(ids.filter { views[$0] == nil }, gone) {
            views[new] = old.view
        }
        return views
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
