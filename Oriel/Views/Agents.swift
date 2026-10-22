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

/// The Agents view's order.
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

/// A workspace's state: an amber dot, the working dots, a green dot or a gray ring; nothing without an agent.
struct StateIcon: View {
    let state: AgentState?
    @Environment(\.look) private var look

    var body: some View {
        Group {
            switch state {
            case .working: WorkingDots()
            case .idle: Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 7, height: 7)
            case let .some(state): Circle().fill(state.color(look)).frame(width: 7, height: 7)
            case nil: Color.clear
            }
        }
        .frame(width: 14, height: 14)
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
    /// An agent pane in the Agents view and the needs-you popover: its tile and badge, name and capsule; its
    /// workspace and tab, and how long ago its state changed. A click selects its workspace and tab and gives it the
    /// keyboard.
    struct AgentButton: View {
        let pane: HostStore.Pane
        let page: Page
        var picked: () -> Void = {}
        @Environment(\.look) private var look

        var body: some View {
            Button {
                page.go(to: pane)
                picked()
            } label: {
                label(pane.state ?? .idle)
            }
            .buttonStyle(ChromeStyle(radius: 10))
            .accessibilityIdentifier("agent.\(pane.id)")
            .accessibilityLabel("\(pane.agentName ?? "agent"), \(page.place(pane))")
            .accessibilityValue(pane.state?.capsule ?? "")
        }

        private func label(_ state: AgentState) -> some View {
            HStack(spacing: 8) {
                ProgramTile(icon: pane.iconID, letter: pane.letter)
                    .overlay(alignment: .topTrailing) { StatusBadge(state: state) }
                    .compositingGroup()
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(pane.agentName ?? "agent").font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(state.capsule).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(state.color(look))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(state.color(look).opacity(0.15), in: .rect(cornerRadius: 4))
                    }
                    HStack {
                        Text(page.place(pane)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let since = pane.since {
                            TimelineView(.everyMinute) { context in Text(age(since, context.date)) }
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
        }

        /// "now", "3m", "2h", "4d".
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

    /// A page's Agents view (D61): its session's agent panes, by priority in groups or in workspace order.
    struct AgentsList: View {
        let page: Page
        let filter: String
        let sort: AgentSort

        var body: some View {
            let rows = page.store.agentPanes.filter { pane in
                [pane.agentName ?? "", page.place(pane)].contains { $0.matches(filter) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if sort == .priority {
                        ForEach([AgentState.needsYou, .working, .finishedUnseen, .idle], id: \.self) { state in
                            let group = rows.filter { $0.state == state }
                            if !group.isEmpty {
                                Text("\(state.capsule) \(group.count)").font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 6)
                                    .accessibilityIdentifier("agents.group.\(state.capsule)")
                                ForEach(group) { AgentButton(pane: $0, page: page) }
                            }
                        }
                    } else {
                        ForEach(rows) { AgentButton(pane: $0, page: page) }
                    }
                }
                .padding([.horizontal, .bottom], 8)
            }
            .scrollIndicators(.never)
        }
    }

    /// The Agents button's popover: the page's agents that need you.
    struct NeedsYouPanel: View {
        let page: Page
        let close: () -> Void

        var body: some View {
            let waiting = page.store.agentPanes.filter { $0.state == .needsYou }
            VStack(alignment: .leading, spacing: 2) {
                Text("Needs you · \(page.id)").font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 2)
                if waiting.isEmpty {
                    Text("Nobody needs you").padding(8).accessibilityIdentifier("agents.popover.empty")
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
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
            let needsYou = pages.list.isEmpty ? 0 : HostStore.all
                .reduce(0) { count, store in count + store.panes.count { $0.state == .needsYou } }
            content
                // A text leaf, as `window.look`.
                .background(alignment: .topLeading) {
                    Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityAddTraits(.isStaticText)
                        .accessibilityLabel("Dock Badge").accessibilityIdentifier("app.badge")
                        .accessibilitySortPriority(-1)
                        .accessibilityValue("\(needsYou)")
                }
                .onChange(of: needsYou, initial: true) { NSApp.dockTile.badgeLabel = needsYou > 0 ? "\(needsYou)" : nil
                }
                .onChange(of: [page.id, page.selectedTab?.id ?? "", appearsActive ? "key" : ""], initial: true) {
                    pages.look(key: appearsActive)
                }
        }
    }

    extension View {
        /// A panel that opens under this view after the pointer rests on it 0.25 s, stays while the pointer moves
        /// into it (0.15 s grace), and closes when the pointer leaves both, on a click outside it, or with Esc. Not
        /// while a mouse button is down (a drag). In the window, not a `.popover`: a popover is a window that takes the
        /// keyboard when it shows, and a resting pointer must not take keys from the terminal.
        func hoverPanel(@ViewBuilder _ panel: @escaping (_ close: @escaping () -> Void) -> some View) -> some View {
            modifier(HoverPanel(panel: panel))
        }
    }

    private struct HoverPanel<Panel: View>: ViewModifier {
        let panel: (_ close: @escaping () -> Void) -> Panel
        @State private var open = false
        @State private var overTrigger = false
        @State private var overPanel = false
        @State private var pending: Task<Void, Never>?
        @State private var monitor: Any?

        func body(content: Content) -> some View {
            content
                .onHover { overTrigger = $0
                    hovered()
                }
                // A click is not a rest: no panel until the pointer comes back (onHover fires only on entering).
                .simultaneousGesture(TapGesture().onEnded {
                    overTrigger = false
                    hovered()
                })
                .overlay(alignment: .bottomTrailing) {
                    if open {
                        panel { show(false) }
                            .onHover { overPanel = $0
                                hovered()
                            }
                            .fixedSize()
                            // Hangs from the trigger's bottom.
                            .offset(y: 4)
                            .frame(height: 0, alignment: .top)
                    }
                }
                .onDisappear { show(false) }
        }

        private func hovered() {
            pending?.cancel()
            let over = overTrigger || overPanel
            guard over != open, !over || NSEvent.pressedMouseButtons == 0 else { return }
            pending = Task {
                try? await Task.sleep(for: .milliseconds(over ? 250 : 150))
                // A drag may have started meanwhile.
                if !Task.isCancelled, !over || NSEvent.pressedMouseButtons == 0 {
                    show(over)
                }
            }
        }

        private func show(_ value: Bool) {
            pending?.cancel()
            open = value
            if value, monitor == nil {
                let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
                monitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
                    guard event.type != .keyDown || event.keyCode == 53 else { return event }
                    let escape = event.type == .keyDown
                    MainActor.assumeIsolated {
                        if escape || !overPanel {
                            show(false)
                        }
                    }
                    return escape ? nil : event
                }
            } else if !value, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
#endif
