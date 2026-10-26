import HerdrKit
import SwiftUI

extension AgentState {
    /// For notifications, the Dock menu and VoiceOver.
    var word: String {
        switch self {
        case .needsYou: "needs you"
        case .working: "working"
        case .finishedUnseen: "finished"
        case .idle: "idle"
        }
    }

    /// The Agents view's capsule.
    var capsule: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .finishedUnseen: "Done"
        case .idle: "Idle"
        }
    }

    func color(_ look: Look) -> Color {
        switch self {
        case .needsYou: look.needsYou
        case .working: look.working
        case .finishedUnseen: look.finished
        case .idle: .secondary
        }
    }
}

enum AgentSort: String {
    case priority, workspace
}

// Rex's three working dots: each fades 0.3 → 0.85 → 0.3 over 1.2 s, 0.2 s after the one before, from the wall
// clock so every tab is in step. Core Animation runs them, at most 15 frames a second, so the app does no work per
// frame (a TimelineView per dots made SwiftUI lay out the window at every tick: phase 25, lane O). Still under Reduce
// Motion (but with `-forceMotion`) and on a sidebar page off to the side.
#if os(macOS)
    struct WorkingDots: NSViewRepresentable {
        @Environment(\.look) private var look
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.offscreen) private var offscreen

        /// One dot, repeated 5.5 pt and 0.2 s apart: as an HStack of 3.5 pt squares 2 pt apart, centered in 14 pt.
        func makeNSView(context _: Context) -> NSView {
            let view = Dots(), dots = CAReplicatorLayer(), dot = CALayer()
            view.wantsLayer = true
            dot.frame = CGRect(x: -0.25, y: 5.25, width: 3.5, height: 3.5)
            dot.cornerRadius = 1.75
            dot.opacity = 0.6
            dots.instanceCount = 3
            dots.instanceTransform = CATransform3DMakeTranslation(5.5, 0, 0)
            dots.instanceDelay = 0.2
            dots.addSublayer(dot)
            view.layer?.addSublayer(dots)
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            guard let dot = view.layer?.sublayers?.first?.sublayers?.first else { return }
            dot.backgroundColor = look.working.resolve(in: context.environment).cgColor
            if reduceMotion && !Animation.forceMotion || offscreen {
                dot.removeAllAnimations()
            } else if dot.animation(forKey: "working") == nil {
                dot.add(Self.fade(in: dot), forKey: "working")
            }
        }

        func sizeThatFits(_: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
            CGSize(width: 14, height: 14)
        }

        /// Clicks go through to the row's button.
        final class Dots: NSView {
            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }

        /// Key times 0, 0.25 and 0.5 of the cycle, eased in and out; rests at 0.3 for the second half. Its phase is
        /// the wall clock's.
        private static func fade(in layer: CALayer) -> CAAnimation {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.3, 0.85, 0.3, 0.3]
            fade.keyTimes = [0, 0.25, 0.5, 1]
            fade.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut), .init(name: .linear)]
            fade.duration = 1.2
            fade.repeatCount = .infinity
            fade.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 15)
            let phase = Date.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2)
            fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - phase
            return fade
        }
    }
#else
    // ponytail: the iOS app draws no agent states yet; real dots when it does.
    struct WorkingDots: View {
        var body: some View {
            Color.clear.frame(width: 14, height: 14)
        }
    }
#endif

extension EnvironmentValues {
    /// A sidebar page off to the side: its dots stand still.
    @Entry var offscreen = false
}

/// A workspace's state: an amber dot, the working dots, a green dot or a gray ring; a faint dot without an agent.
struct StateIcon: View {
    let state: AgentState?
    @Environment(\.look) private var look

    var body: some View {
        Group {
            switch state {
            case .working: WorkingDots()
            case .idle: Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 7, height: 7)
            case let .some(state): Circle().fill(state.color(look)).frame(width: 7, height: 7)
            // A workspace with no agent: a quiet dot, so the slot does not look missing.
            case nil: Circle().fill(.tertiary).frame(width: 4, height: 4)
            }
        }
        .frame(width: 14, height: 14)
    }
}

struct StateCapsule: View {
    let state: AgentState
    @Environment(\.look) private var look

    var body: some View {
        Text(state.capsule).font(.system(size: 11, weight: .medium))
            .foregroundStyle(state.color(look))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(state.color(look).opacity(0.15), in: .rect(cornerRadius: 4))
    }
}

/// The 7 pt dot on a program tile's top-right for needs you and finished, cutting a 1.5 pt ring out of the
/// tile (Glass has no solid background color). In the tile's compositing group.
struct StatusBadge: View {
    let state: AgentState?
    @Environment(\.look) private var look

    var body: some View {
        if let state, state >= .finishedUnseen {
            ZStack {
                Circle().frame(width: 10, height: 10).blendMode(.destinationOut)
                Circle().fill(state.color(look)).frame(width: 7, height: 7)
            }
            .offset(x: 4, y: -4)
        }
    }
}

#if os(macOS)
    /// An agent pane in the Agents view and the Agents button's panel. A click selects its workspace and tab and gives
    /// it the keyboard. Lit like the selected workspace row while it is the shown tab's keyboard card (user, phase 25).
    struct AgentButton: View {
        let pane: HostStore.Pane
        let page: Page
        /// Line 2; "‹workspace› · ‹tab›" when nil.
        var place: String?
        var picked: () -> Void = {}
        @Environment(\.look) private var look

        var body: some View {
            Button {
                page.go(to: pane)
                picked()
            } label: {
                label(pane.state ?? .idle)
            }
            .buttonStyle(ChromeStyle(selected: lit, radius: 10))
            .accessibilityIdentifier("agent.\(pane.id)")
            .accessibilityLabel("\(title), \(line2)")
            .accessibilityValue(pane.state?.capsule ?? "")
            .accessibilityAddTraits(lit ? .isSelected : [])
        }

        /// The pane's name when it has one, else the agent's (user, phase 25).
        private var title: String {
            pane.label ?? pane.agentName ?? "agent"
        }

        private var line2: String {
            place ?? page.place(pane)
        }

        private var lit: Bool {
            page.keyboardCard(page.selectedTab?.id) === pane
        }

        private func label(_ state: AgentState) -> some View {
            HStack(spacing: 8) {
                ProgramTile(icon: pane.iconID, letter: pane.letter)
                    .overlay(alignment: .topTrailing) { StatusBadge(state: state) }
                    .compositingGroup()
                // Line 1 the name, the capsule and the age on one centered line; line 2 the place (user, phase 24).
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 13)).lineLimit(1)
                            .foregroundStyle(lit ? look.selected : look.chrome)
                        Spacer(minLength: 0)
                        StateCapsule(state: state)
                        if let since = pane.since {
                            TimelineView(.everyMinute) { context in Text(age(since, context.date)) }
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Text(line2).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
        }

        private func age(_ since: Date, _ now: Date) -> String {
            let minutes = Int(now.timeIntervalSince(since) / 60)
            return switch minutes {
            case ..<1: "now"
            case ..<60: "\(minutes)m"
            case ..<(24 * 60): "\(minutes / 60)h"
            default: "\(minutes / (24 * 60))d"
            }
        }
    }

    extension HostStore {
        /// The agent panes in herdr's order of workspaces, tabs and panes.
        var agentPanes: [Pane] {
            workspaces.flatMap(\.tabs).flatMap { panes(in: $0.id).filter { $0.state != nil } }
        }
    }

    /// A page's Agents view (D61): its session's agent panes, by priority or in workspace order, in groups that fold.
    struct AgentsList: View {
        let page: Page
        let filter: String
        let sort: AgentSort
        /// The folded groups, a line each, "‹machine› ‹session› ‹sort› ‹group›": per session and order, kept across
        /// relaunches (user, phase 27). ponytail: a closed workspace's line stays (and folds a new workspace that gets
        /// its id); prune them if that is ever seen.
        @AppStorage("agentsFolded") private var folded = ""
        @State private var position = ScrollPosition(idType: String.self)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let folded = Set(folded.split(separator: "\n").map(String.init))
            ScrollView {
                // Lazy: only the rows in view are built, of a hundred agents or more (phase 29).
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.groups(page, filter: filter, sort: sort), id: \.id) { group in
                        let open = !folded.contains(group.key)
                        label(group.label, group.rows.count, group.key, open: open, id: group.id)
                        if open {
                            ForEach(group.rows) { row($0) }
                        }
                    }
                }
                .padding(Sidebar.rowInsets)
                // Built anew for the other order: the lazy stack kept the first order's rows (line 2 with the
                // workspace) for the same panes.
                .id(sort)
            }
            .scrollIndicators(.never)
            .scrollPosition($position)
            // The lit row into view, just enough, however its pane was shown (phase 31). The lazy stack finds a row it
            // has not built.
            .onChange(of: page.keyboardCard(page.selectedTab?.id)?.id, initial: true) { _, id in
                if let id {
                    position.scrollTo(id: id)
                }
            }
        }

        struct Group {
            let label: String, key: String, id: String
            let rows: [HostStore.Pane]
        }

        /// The groups with rows, in order, of the agents that match the filter: by priority, or under each workspace's
        /// name. `key` folds one: "‹machine› ‹session› ‹sort› ‹group›".
        static func groups(_ page: Page, filter: String, sort: AgentSort) -> [Group] {
            let rows = page.store.agentPanes.filter { pane in
                [pane.label, pane.agentName, page.place(pane)].compactMap(\.self).contains { $0.matches(filter) }
            }
            let key = { (group: String) in "\(page.store.machine.id) \(page.id) \(sort.rawValue) \(group)" }
            let groups = switch sort {
            case .priority:
                [AgentState.needsYou, .working, .finishedUnseen, .idle].map { state in
                    Group(label: state.capsule, key: key("\(state)"), id: "agents.group.\(state.capsule)",
                          rows: rows.filter { $0.state == state })
                }
            case .workspace:
                page.store.workspaces.map { workspace in
                    Group(label: workspace.label, key: key(workspace.id), id: "agents.workspace.\(workspace.id)",
                          rows: rows.filter { pane in workspace.tabs.contains { $0.id == pane.tabID } })
                }
            }
            return groups.filter { !$0.rows.isEmpty }
        }

        /// Goes to the agent row above (-1) or below (1) the lit one, round the ends, as a click on it does; a folded
        /// group's rows are skipped (a three-finger swipe, phase 31).
        static func step(_ offset: Int, _ page: Page, filter: String, sort: AgentSort) {
            let folded = Set((UserDefaults.standard.string(forKey: "agentsFolded") ?? "").split(separator: "\n")
                .map(String.init))
            let rows = groups(page, filter: filter, sort: sort).filter { !folded.contains($0.key) }.flatMap(\.rows)
            guard !rows.isEmpty else { return }
            let lit = rows.firstIndex { page.keyboardCard(page.selectedTab?.id) === $0 }
            page.go(to: rows[lit.map { ($0 + offset + rows.count) % rows.count } ?? (offset > 0 ? 0 : rows.count - 1)])
        }

        /// A section label, as in a macOS sidebar: smaller than the title, with room above (user, phase 25). A click
        /// folds or unfolds its rows; a folded group keeps its label and count (user, phase 27).
        private func label(_ text: String, _ count: Int, _ key: String, open: Bool, id: String) -> some View {
            Button {
                var keys = Set(folded.split(separator: "\n").map(String.init))
                if keys.remove(key) == nil {
                    keys.insert(key)
                }
                withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                    folded = keys.joined(separator: "\n")
                }
            } label: {
                GroupLabel(text: "\(text) \(count)", open: open)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(text) \(count)")
            .accessibilityValue(open ? "expanded" : "collapsed")
            .accessibilityIdentifier(id)
            .padding(.horizontal, 8).padding(.top, 12)
        }

        /// Under its workspace's name, line 2 holds only the tab (user, phase 25).
        private func row(_ pane: HostStore.Pane) -> some View {
            let tabs = sort == .workspace ? page.store.workspace(of: pane.tabID)?.tabs : nil
            return AgentButton(pane: pane, page: page, place: tabs?.first { $0.id == pane.tabID }.map(page.titleText))
                .hoverPanel(place: .beside) { close in HoverCard(tabID: pane.tabID, page: page, close: close) }
        }
    }

    /// A group label's text and chevron: the chevron points right while folded, and shows down only under the
    /// pointer while open, as in a macOS sidebar.
    private struct GroupLabel: View {
        let text: String
        let open: Bool
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 4) {
                Text(text).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                    .opacity(open && !hovering ? 0 : 1)
            }
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            .contentShape(.rect)
            .onHover { hovering = $0 }
        }
    }

    /// The Dock badge over every open page (also `app.badge`, for tests), and the tab the user looks at (D14).
    struct AgentsWatch: ViewModifier {
        let pages: WindowPages
        let page: Page
        @Environment(\.appearsActive) private var appearsActive

        func body(content: Content) -> some View {
            // Each session once over every window. This window's list is read too, so a page it opens or closes counts.
            // ponytail: `HostStore.all` is not observed, so this window's `app.badge` may lag a store only another
            // window shows until one of this window's own changes; the Dock tile is right (the last writer counts all).
            let needsYou = pages.list.isEmpty ? 0 : HostStore.needsYou
            content
                .testValue("app.badge", "Dock Badge", "\(needsYou)")
                .onChange(of: needsYou, initial: true) { HostStore.showBadge() }
                .onChange(of: [page.id, page.selectedTab?.id ?? "", appearsActive ? "key" : ""], initial: true) {
                    pages.look(key: appearsActive)
                }
        }
    }
#endif
