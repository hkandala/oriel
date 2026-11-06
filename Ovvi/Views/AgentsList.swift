import HerdrKit
import SwiftUI

/// A page's Agents view (D61): its pinned agents on top, then one list of its live agents, newest change of state
/// first, then the Settled shelf at the foot. Rows hold still while the pointer is over the list.
struct AgentsList: View {
    let page: Page
    let filter: String
    private var settings = AppSettings()
    /// The order on screen while a newer one waits: for the pointer to leave the list, and 1 s after the last change.
    /// ponytail: agents that change more often than once a second hold the order until they stop.
    @State private var held: Arrangement?
    @State private var hovering = false
    /// Each change and each time the pointer leaves: the release waits 1 s after the last one.
    @State private var moves = 0
    /// A pin or a settle by hand changed the order: the user's own move shows at once.
    @State private var acted = false
    @State private var viewport = 0.0
    @State private var position = ScrollPosition(idType: String.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The parts' pane ids, in order, for `filter`.
    struct Arrangement: Equatable {
        var pinned: [String] = [], live: [String] = [], settled: [String] = []
        var filter = ""

        /// These rows with `target`'s: the gone ones out, the new ones at the end of their part. A row that moves to
        /// another part waits in its old one.
        func showing(_ target: Arrangement) -> Arrangement {
            let ids = Set(pinned + live + settled), all = Set(target.pinned + target.live + target.settled)
            let part = { (held: [String], new: [String]) in
                held.filter(all.contains) + new.filter { !ids.contains($0) }
            }
            return Arrangement(pinned: part(pinned, target.pinned), live: part(live, target.live),
                               settled: part(settled, target.settled), filter: target.filter)
        }
    }

    var body: some View {
        // Each minute: Settled takes in agents idle past the setting. The time now, not the entry's: that is the
        // minute's start, before an agent that went idle in it.
        TimelineView(.everyMinute) { _ in
            arranged(now: .now)
        }
        .onHover { inside in
            hovering = inside
            if !inside {
                moves += 1
            }
        }
        .task(id: moves) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled, !hovering {
                slide { held = nil }
            }
        }
        // The lit row into view, just enough, without motion, however its pane was shown. Again once laid out: on the
        // stack's first layout the scroll can miss.
        .onChange(of: page.keyboardCard(page.selectedTab?.id)?.id ?? "", initial: true) { _, id in
            withTransaction(\.animation, nil) { position.scrollTo(id: id) }
            Task { position.scrollTo(id: id) }
        }
    }

    /// The list at `now`: on screen the held order, or the new one.
    private func arranged(now: Date) -> some View {
        let target = Self.arrange(page, filter: filter, settings: settings, now: now)
        let shown = held?.showing(target) ?? target
        return list(shown, target)
            .onChange(of: target) { old, new in
                // A new filter is the user's own move too.
                guard !acted, old.filter == new.filter else {
                    acted = false
                    slide { held = nil }
                    return
                }
                held = held ?? old
                moves += 1
            }
            // What ⌥ + swipe steps through: the rows on screen.
            .onChange(of: shown, initial: true) { page.agentsShown = shown }
    }

    /// `shown` on screen; the menus and buttons act on `target`, where each row is now.
    private func list(_ shown: Arrangement, _ target: Arrangement) -> some View {
        let panes = Dictionary(page.store.agentPanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = { (ids: [String]) in ids.compactMap { panes[$0] } }
        let pinned = Set(target.pinned), settled = Set(target.settled)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Lazy: only the rows in view are built, of a hundred agents or more. One ForEach: a lazy stack keeps a
                // row's view by its id, so a row moved to another ForEach kept its old one (not pinned).
                let top = rows(shown.pinned), items = top + rows(shown.live)
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { pane in
                        row(pane, pinned: pinned.contains(pane.id), settled: settled.contains(pane.id))
                        if pane === top.last {
                            Divider().padding(.horizontal, 8).padding(.vertical, 4)
                        }
                    }
                }
                // The shelves at the foot while the list is short.
                Spacer(minLength: 12)
                if !shown.settled.isEmpty {
                    Shelf(label: "Settled", count: shown.settled.count, page: page) {
                        ForEach(rows(shown.settled)) { pane in
                            row(pane, pinned: pinned.contains(pane.id), settled: settled.contains(pane.id), age: true)
                        }
                    }
                }
            }
            .padding(Sidebar.rowInsets)
            .frame(minHeight: viewport, alignment: .top)
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Double.self) { $0.containerSize.height } action: { viewport = $1 }
    }

    private func row(_ pane: HostStore.Pane, pinned: Bool, settled: Bool, age: Bool = false) -> some View {
        AgentButton(pane: pane, page: page, age: age ? pane.since : nil, pinned: pinned, pin: { pin(pane, pinned) })
            .hoverPanel(place: .beside) { close in HoverCard(tabID: pane.tabID, page: page, close: close) }
            .contextMenu {
                Button(pinned ? "Unpin" : "Pin") { pin(pane, pinned) }
                Button(settled ? "Unsettle" : "Settle") { settle(pane, settled) }
                    // Needs you and an unseen finish never settle; working ends it.
                    .disabled(pinned || pane.state != .idle)
            }
    }

    private func slide(_ change: () -> Void) {
        withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2), change)
    }

    private func pin(_ pane: HostStore.Pane, _ pinned: Bool) {
        var pins = [AgentPin](json: settings.pins)
        let mine = { (pin: AgentPin) in
            pin.machine == page.store.machine.id && pin.session == page.store.session && pane.holds(pin)
        }
        if pinned {
            pins.removeAll(where: mine)
        } else if let pin = pane.pin(in: page.store), !pins.contains(where: mine) {
            pins.append(pin)
        }
        act { settings.pins = pins.json }
    }

    private func settle(_ pane: HostStore.Pane, _ settled: Bool) {
        act { page.store.settles[pane.settleKey] = AgentSettle(since: pane.since, settled: !settled) }
    }

    /// The user's own move: at once, with the slide. Only a write that changes the order is waited for.
    private func act(_ write: () -> Void) {
        let before = Self.arrange(page, filter: filter, settings: settings, now: .now)
        held = nil
        slide(write)
        acted = Self.arrange(page, filter: filter, settings: settings, now: .now) != before
    }

    /// Where each agent that matches the filter goes: pinned (in pin order), settled (idle and seen longer than the
    /// setting, or by hand until its next change), else the list; newest change of state first.
    static func arrange(_ page: Page, filter: String, settings: AppSettings, now: Date) -> Arrangement {
        let store = page.store
        let panes = store.agentPanes.filter { pane in
            [pane.agentTitle, pane.agentName, page.place(pane)].compactMap(\.self).contains { $0.matches(filter) }
        }
        let pins = [AgentPin](json: settings.pins)
            .filter { $0.machine == store.machine.id && $0.session == store.session }
        var pinned: [HostStore.Pane] = []
        for pin in pins {
            if let pane = panes.first(where: { $0.holds(pin) }), !pinned.contains(where: { $0 === pane }) {
                pinned.append(pane)
            }
        }
        var arrangement = Arrangement(pinned: pinned.map(\.id), filter: filter)
        // Stable: herdr's order of workspaces, tabs and panes among equals.
        let rest = panes.filter { pane in !pinned.contains { $0 === pane } }.enumerated()
            .sorted { ($0.element.changeSeq ?? -1, -$0.offset) > ($1.element.changeSeq ?? -1, -$1.offset) }
            .map(\.element)
        for pane in rest {
            let byHand = store.settles[pane.settleKey]?.settled
            let after = settings.settleAfter
            let old = after > 0 && pane.since.map { now.timeIntervalSince($0) >= after } == true
            if pane.state == .idle, byHand ?? old {
                arrangement.settled.append(pane.id)
            } else {
                arrangement.live.append(pane.id)
            }
        }
        return arrangement
    }

    /// Goes to the agent row above (-1) or below (1) the lit one, round the ends, as a click on it does (a
    /// ⌥ + swipe), in the order on screen. Floated panes are skipped: a click on one brings its window forward, and
    /// the lit row would stay.
    static func step(_ offset: Int, _ page: Page) {
        let shown = page.agentsShown
        let ids = shown.pinned + shown.live + (page.opens("Settled") ? shown.settled : [])
        let rows = ids.compactMap(page.store.pane).filter { !page.floats($0) }
        guard !rows.isEmpty else { return }
        let card = page.keyboardCard(page.selectedTab?.id), lit = rows.firstIndex { $0 === card }
        page.go(to: rows[lit.map { ($0 + offset + rows.count) % rows.count } ?? (offset > 0 ? 0 : rows.count - 1)])
    }
}
