import HerdrKit
import SwiftUI

/// A page's Agents view (D61): its pinned agents on top, then one list of its live agents, newest change of state
/// first, then the Settled shelf at the foot. Rows hold still while the pointer is over the list.
struct AgentsList: View {
    let page: Page
    let filter: String
    private var settings = AppSettings()
    /// The order on screen while a newer one waits: for the pointer to leave the list, and 1 s after the last change.
    @State private var held: Arrangement?
    @State private var hovering = false
    @State private var moves = 0
    /// A pin or a settle by hand: the user's own move shows at once.
    @State private var acted = false
    @State private var viewport = 0.0
    @State private var position = ScrollPosition(idType: String.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The parts' pane ids, in order, for `filter`.
    struct Arrangement: Equatable {
        var pinned: [String] = [], live: [String] = [], settled: [String] = []
        var filter = ""

        /// These rows with `target`'s: the gone ones out, the new ones on top of their part.
        func showing(_ target: Arrangement) -> Arrangement {
            // A row that moves to another part waits in its old one.
            let ids = Set(pinned + live + settled), all = Set(target.pinned + target.live + target.settled)
            let part = { (held: [String], new: [String]) in
                new.filter { !ids.contains($0) } + held.filter(all.contains)
            }
            return Arrangement(pinned: part(pinned, target.pinned), live: part(live, target.live),
                               settled: part(settled, target.settled), filter: target.filter)
        }
    }

    var body: some View {
        // Each minute, for the ages and Settled; quicker for a setting under two minutes (tests).
        let after = settings.settleAfter
        TimelineView(.periodic(from: .now, by: after > 0 ? min(60, max(1, after / 2)) : 60)) { context in
            let target = Self.arrange(page, filter: filter, settings: settings, now: context.date)
            let shown = held?.showing(target) ?? target
            list(shown)
                .onChange(of: target) { old, new in
                    // A new filter is the user's own move too.
                    guard !acted, old.filter == new.filter else {
                        held = nil
                        acted = false
                        return
                    }
                    held = held ?? old
                    release()
                }
        }
        .onHover { inside in
            hovering = inside
            if !inside {
                release()
            }
        }
        .onChange(of: page.store.agentPanes.map(\.pinState)) { keep() }
        // The lit row into view, just enough, without motion, however its pane was shown. Again once laid out: on the
        // stack's first layout the scroll can miss.
        .onChange(of: page.keyboardCard(page.selectedTab?.id)?.id ?? "", initial: true) { _, id in
            withTransaction(\.animation, nil) { position.scrollTo(id: id) }
            Task { position.scrollTo(id: id) }
        }
    }

    private func list(_ shown: Arrangement) -> some View {
        let panes = Dictionary(page.store.agentPanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = { (ids: [String]) in ids.compactMap { panes[$0] } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Lazy: only the rows in view are built, of a hundred agents or more.
                // One ForEach: a lazy stack keeps a row's view by its id, so a row moved to another ForEach kept
                // its old one (not pinned).
                let pinned = rows(shown.pinned),
                    items = pinned.map { ($0, true) } + rows(shown.live).map { ($0, false) }
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.0.id) { pane, isPinned in
                        row(pane, pinned: isPinned)
                        if pane === pinned.last {
                            Divider().padding(.horizontal, 8).padding(.vertical, 4)
                        }
                    }
                }
                // The shelves at the foot while the list is short.
                Spacer(minLength: 12)
                if !shown.settled.isEmpty {
                    Shelf(label: "Settled", count: shown.settled.count, page: page) {
                        ForEach(rows(shown.settled)) { row($0, settled: true) }
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

    private func row(_ pane: HostStore.Pane, pinned: Bool = false, settled: Bool = false) -> some View {
        AgentButton(pane: pane, page: page, age: settled ? pane.since : nil, pinned: pinned, pin: { pin(pane, pinned) })
            .hoverPanel(place: .beside) { close in HoverCard(tabID: pane.tabID, page: page, close: close) }
            .contextMenu {
                Button(pinned ? "Unpin" : "Pin") { pin(pane, pinned) }
                Button(settled ? "Unsettle" : "Settle") { settle(pane, settled) }
                    // Needs you and an unseen finish never settle; working ends it.
                    .disabled(pinned || pane.state != .idle)
            }
    }

    /// The order waits until the pointer is off the list and 1 s passed since the last change, then slides there.
    private func release() {
        moves += 1
        let move = moves
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard move == moves, !hovering else { return }
            withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) { held = nil }
        }
    }

    private func pin(_ pane: HostStore.Pane, _ pinned: Bool) {
        var pins = [AgentPin](json: settings.pins)
        if pinned {
            pins.removeAll { mine($0.machine, $0.session) && pane.holds($0) }
        } else if let pin = pane.pin(in: page.store) {
            pins.append(pin)
        }
        act { settings.pins = pins.json }
    }

    private func settle(_ pane: HostStore.Pane, _ settled: Bool) {
        guard let key = pane.pinKey else { return }
        var settles = [AgentSettle](json: settings.settles).filter { !mine($0.machine, $0.session) || $0.key != key }
        settles.append(AgentSettle(machine: page.store.machine.id, session: page.store.session, key: key,
                                   seq: pane.changeSeq, settled: !settled))
        act { settings.settles = settles.json }
    }

    /// The user's own move: at once, with the slide.
    private func act(_ write: () -> Void) {
        acted = true
        held = nil
        withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2), write)
    }

    private func mine(_ machine: String, _ session: String) -> Bool {
        machine == page.store.machine.id && session == page.store.session
    }

    /// Keeps each pin's title, folder and key as its pane's now (the key moves to the session once the agent reports
    /// one); drops pins that nothing can bring back (closed, with no session) and settles past their change.
    private func keep() {
        guard page.store.last != nil else { return }
        let panes = page.store.agentPanes
        let pins = [AgentPin](json: settings.pins).compactMap { pin -> AgentPin? in
            guard mine(pin.machine, pin.session) else { return pin }
            let pane = panes.first { $0.holds(pin) }
            return pane?.pin(in: page.store) ?? (pin.agent == nil ? nil : pin)
        }
        if pins.json != settings.pins {
            settings.pins = pins.json
        }
        let settles = [AgentSettle](json: settings.settles).filter { settle in
            !mine(settle.machine, settle.session)
                || panes.contains { $0.pinKey == settle.key && $0.changeSeq == settle.seq }
        }
        if settles.json != settings.settles {
            settings.settles = settles.json
        }
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
        let settles = [AgentSettle](json: settings.settles)
            .filter { $0.machine == store.machine.id && $0.session == store.session }
        let pinned = pins.compactMap { pin in panes.first { $0.holds(pin) } }
        var arrangement = Arrangement(pinned: pinned.map(\.id), filter: filter)
        // Stable: herdr's order of workspaces, tabs and panes among equals.
        let rest = panes.filter { pane in !pinned.contains { $0 === pane } }.enumerated()
            .sorted { ($0.element.changeSeq ?? -1, -$0.offset) > ($1.element.changeSeq ?? -1, -$1.offset) }
            .map(\.element)
        for pane in rest {
            let byHand = settles.first { $0.key == pane.pinKey && $0.seq == pane.changeSeq }?.settled
            let idle = pane.state == .idle, after = settings.settleAfter
            let old = after > 0 && pane.since.map { now.timeIntervalSince($0) >= after } == true
            if idle, byHand ?? old {
                arrangement.settled.append(pane.id)
            } else {
                arrangement.live.append(pane.id)
            }
        }
        return arrangement
    }

    /// Goes to the agent row above (-1) or below (1) the lit one, round the ends, as a click on it does (a
    /// ⌥ + swipe): pinned, the list, then Settled while it is open. Floated panes are skipped: a click on one brings
    /// its window forward, and the lit row would stay.
    static func step(_ offset: Int, _ page: Page, filter: String) {
        let arrangement = arrange(page, filter: filter, settings: AppSettings(), now: .now)
        let open = (UserDefaults.standard.string(forKey: "agentsOpen") ?? "").split(separator: "\n")
            .contains { $0 == "\(page.store.machine.id) \(page.id) Settled" }
        let ids = arrangement.pinned + arrangement.live + (open ? arrangement.settled : [])
        let rows = ids.compactMap(page.store.pane).filter { !page.floats($0) }
        guard !rows.isEmpty else { return }
        let card = page.keyboardCard(page.selectedTab?.id), lit = rows.firstIndex { $0 === card }
        page.go(to: rows[lit.map { ($0 + offset + rows.count) % rows.count } ?? (offset > 0 ? 0 : rows.count - 1)])
    }
}

private extension HostStore.Pane {
    /// What a pin keeps of it, and what ends a settle.
    var pinState: [String?] {
        [pinKey, agentTitle, folder, changeSeq.map(String.init)]
    }
}
