import HerdrKit
import SwiftUI

/// The selected tab's page: its cards in herdr's layout. A switch shows another tab's page at once (a view of its own
/// per tab, made by `Detail`).
struct TabPage: View {
    let tab: HostStore.Tab
    let page: Page
    /// A kept page out of view (`TabPages`) leaves the accessibility tree. Not by `accessibilityHidden(false)` when
    /// shown, which overrides the hidden ones inside (a zoom's cards under it).
    @Environment(\.pageHidden) private var hidden

    var body: some View {
        Group {
            if let tree = tab.tree {
                let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                SplitLayout(tree: tree, zoomed: zoomed, page: page, tabID: tab.id)
                    .padding(Self.inset)
            } else {
                Text("No layout for this tab").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: \.size) { page.terminals.pageSize = $0 }
        .accessibilityElement(children: hidden ? .ignore : .contain)
        .accessibilityIdentifier(hidden ? "" : "page.\(tab.id)")
    }

    /// A page's cards inside its page: room for the cards' outer stroke and shadow.
    static let inset = EdgeInsets(top: 4, leading: gap, bottom: gap, trailing: gap)

    /// The cards' area in a page of this size.
    static func area(_ size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width - inset.leading - inset.trailing,
               height: size.height - inset.top - inset.bottom)
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
                        .overlay { CardFlash(store: page.store, id: card.id) }
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
