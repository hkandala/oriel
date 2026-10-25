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

/// Rex's three working dots: each fades 0.3 → 0.85 → 0.3 over 1.2 s, 0.2 s after the one before, from the wall
/// clock so every tab is in step. At most 15 frames a second; still under Reduce Motion.
struct WorkingDots: View {
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreen) private var offscreen

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || offscreen)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0 ..< 3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.75).fill(look.working).frame(width: 3.5, height: 3.5)
                        .opacity(reduceMotion ? 0.6 : Self.opacity(time - 0.2 * Double(index)))
                }
            }
            .frame(width: 14, height: 14)
        }
        .accessibilityHidden(true)
    }

    /// Key times 0, 0.25 and 0.5 of the cycle, eased in and out; rests at 0.3 for the second half.
    static func opacity(_ time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 1.2) / 1.2
        let ease = { (value: Double) in value * value * (3 - 2 * value) }
        return switch phase {
        case ..<0.25: 0.3 + 0.55 * ease(phase / 0.25)
        case ..<0.5: 0.85 - 0.55 * ease((phase - 0.25) / 0.25)
        default: 0.3
        }
    }
}

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
    /// An agent pane in the Agents view and the needs-you popover. A click selects its workspace and tab and gives it
    /// the keyboard. Lit like the selected workspace row while it is the shown tab's keyboard card (user, phase 25).
    struct AgentButton: View {
        let pane: HostStore.Pane
        let page: Page
        /// Line 2; "‹workspace› · ‹tab›" when nil.
        var place: String?
        var picked: () -> Void = {}
        @Environment(\.look) private var look

        var body: some View {
            let lit = page.keyboardCard(page.selectedTab?.id) === pane
            Button {
                page.go(to: pane)
                picked()
            } label: {
                label(pane.state ?? .idle, lit: lit)
            }
            .buttonStyle(ChromeStyle(selected: lit, radius: 10))
            .accessibilityIdentifier("agent.\(pane.id)")
            .accessibilityLabel("\(title), \(place ?? page.place(pane))")
            .accessibilityValue(pane.state?.capsule ?? "")
            .accessibilityAddTraits(lit ? .isSelected : [])
        }

        /// The pane's name when it has one, else the agent's (user, phase 25).
        private var title: String {
            pane.label ?? pane.agentName ?? "agent"
        }

        private func label(_ state: AgentState, lit: Bool) -> some View {
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
                    Text(place ?? page.place(pane)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
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
            workspaces.flatMap(\.tabs).flatMap { tab in panes.filter { $0.tabID == tab.id && $0.state != nil } }
        }
    }

    /// A page's Agents view (D61): its session's agent panes, by priority or in workspace order, in groups.
    struct AgentsList: View {
        let page: Page
        let filter: String
        let sort: AgentSort

        var body: some View {
            let rows = page.store.agentPanes.filter { pane in
                [pane.agentName ?? "", page.place(pane)].contains { $0.matches(filter) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if sort == .priority {
                        ForEach([AgentState.needsYou, .working, .finishedUnseen, .idle], id: \.self) { state in
                            let group = rows.filter { $0.state == state }
                            if !group.isEmpty {
                                label("\(state.capsule) \(group.count)", id: "agents.group.\(state.capsule)")
                                ForEach(group) { row($0) }
                            }
                        }
                    } else {
                        // Under each workspace's name, so line 2 holds only the tab (user, phase 25).
                        ForEach(page.store.workspaces) { workspace in
                            let tabs = workspace.tabs
                            let group = rows.filter { pane in tabs.contains { $0.id == pane.tabID } }
                            if !group.isEmpty {
                                label(workspace.label, id: "agents.workspace.\(workspace.id)")
                                ForEach(group) { pane in
                                    row(pane, place: tabs.first { $0.id == pane.tabID }.map(page.titleText))
                                }
                            }
                        }
                    }
                }
                .padding(Sidebar.rowInsets)
            }
            .scrollIndicators(.never)
        }

        private func label(_ text: String, id: String) -> some View {
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, 8).padding(.top, 6)
                .accessibilityIdentifier(id)
        }

        private func row(_ pane: HostStore.Pane, place: String? = nil) -> some View {
            AgentButton(pane: pane, page: page, place: place)
                .hoverPanel(place: .beside) { close in HoverCard(tabID: pane.tabID, page: page, close: close) }
        }
    }

    /// The Agents button's popover: the page's agents that need you.
    struct NeedsYouPanel: View {
        let page: Page
        let close: () -> Void

        var body: some View {
            let waiting = page.store.agentPanes.filter { $0.state == .needsYou }
            VStack(alignment: .leading, spacing: 2) {
                // Empty: the words alone, no header (user, phase 24).
                if waiting.isEmpty {
                    Text("All caught up").padding(8).accessibilityIdentifier("agents.popover.empty")
                } else {
                    Text("Needs you · \(page.id)").font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.bottom, 2)
                        .accessibilityIdentifier("agents.popover.header")
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(waiting) { AgentButton(pane: $0, page: page, picked: close) }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 440)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(width: 320, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("agents.popover")
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
