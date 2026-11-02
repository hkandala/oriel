import HerdrKit
import SwiftUI

extension AgentState {
    /// For notifications, the Dock menu, a tab's announcement and VoiceOver.
    var word: String {
        switch self {
        case .needsYou: "needs you"
        case .working: "working"
        case .finishedUnseen: "finished"
        case .idle: "idle"
        }
    }

    /// Its word in a `StateLabel` and the Agents view's group labels.
    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .finishedUnseen: "Done"
        case .idle: "Idle"
        }
    }

    /// Oriel's own: a raised hand, macOS's spinner (drawn by `Spinner`) and a check.
    var symbol: String {
        switch self {
        case .needsYou: "hand.raised.fill"
        case .working: "progress.indicator"
        case .finishedUnseen: "checkmark.circle"
        case .idle: "circle"
        }
    }

    /// Its `StateLabel`, none while idle (t3code shows none for a settled thread); Working counts its time from
    /// `since`.
    func label(_ look: Look, since: Date? = nil) -> StateLabel? {
        self == .idle ? nil : StateLabel(
            text: title,
            symbol: symbol,
            color: color(look),
            since: self == .working ? since : nil,
        )
    }

    /// Needs you or done and not seen: its row's name is medium, as t3code's rows that do not recede.
    var calls: Bool {
        self >= .finishedUnseen
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

/// An agent pane in the Agents view and the Agents button's panel. A click selects its workspace and tab and gives
/// it the keyboard. Lit like the selected workspace row while it is the shown tab's keyboard card.
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
        .accessibilityValue(pane.state?.title ?? "")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    private var title: String {
        pane.agentTitle ?? "agent"
    }

    private var line2: String {
        place ?? page.place(pane)
    }

    private var lit: Bool {
        page.keyboardCard(page.selectedTab?.id) === pane
    }

    private func label(_ state: AgentState) -> some View {
        HStack(spacing: 8) {
            // No badge: the state label says it.
            ProgramTile(icon: pane.iconID, letter: pane.letter)
            // Line 1 the name and, as t3code's thread rows, the state or (idle) the age on one centered line; line 2
            // the place.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: state.calls ? .medium : .regular)).lineLimit(1)
                        .foregroundStyle(lit ? look.selected : look.chrome)
                    Spacer(minLength: 0)
                    if let label = state.label(look, since: pane.since) {
                        label
                    } else if let since = pane.since {
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
    /// relaunches. ponytail: a closed workspace's line stays (and folds a new workspace that gets
    /// its id); prune them if that is ever seen.
    @AppStorage(foldedKey) private var folded = ""
    static let foldedKey = "agentsFolded"
    @State private var position = ScrollPosition(idType: String.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let folded = Self.keys(folded)
        ScrollView {
            // Lazy: only the rows in view are built, of a hundred agents or more.
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Self.groups(page, filter: filter, sort: sort)) { group in
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
        // The lit row into view, just enough, without motion, however its pane was shown, and in a stack made anew
        // (the view opened, the other order); the lazy stack finds a row it has not built. Again once laid out: on
        // the stack's first layout the scroll can miss.
        .onChange(of: [page.keyboardCard(page.selectedTab?.id)?.id ?? "", sort.rawValue], initial: true) {
            let id = $1[0]
            withTransaction(\.animation, nil) { position.scrollTo(id: id) }
            Task { position.scrollTo(id: id) }
        }
    }

    struct Group: Identifiable {
        let label: String, key: String, id: String
        let rows: [HostStore.Pane]
    }

    /// The groups with rows, in order, of the agents that match the filter: by priority, or under each workspace's
    /// name. `key` folds one: "‹machine› ‹session› ‹sort› ‹group›".
    static func groups(_ page: Page, filter: String, sort: AgentSort) -> [Group] {
        let rows = page.store.agentPanes.filter { pane in
            [pane.agentTitle, pane.agentName, page.place(pane)].compactMap(\.self).contains { $0.matches(filter) }
        }
        let key = { (group: String) in "\(page.store.machine.id) \(page.id) \(sort.rawValue) \(group)" }
        let groups = switch sort {
        case .priority:
            [AgentState.needsYou, .working, .finishedUnseen, .idle].map { state in
                Group(label: state.title, key: key("\(state)"), id: "agents.group.\(state.title)",
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

    /// Goes to the agent row above (-1) or below (1) the lit one, round the ends, as a click on it does (a
    /// ⌥ + swipe). A folded group's rows are skipped, and floated panes: a click on one brings
    /// its window forward, and the lit row would stay.
    static func step(_ offset: Int, _ page: Page, filter: String, sort: AgentSort) {
        let folded = keys(UserDefaults.standard.string(forKey: foldedKey) ?? "")
        let rows = groups(page, filter: filter, sort: sort).filter { !folded.contains($0.key) }.flatMap(\.rows)
            .filter { !page.floats($0) }
        guard !rows.isEmpty else { return }
        let card = page.keyboardCard(page.selectedTab?.id), lit = rows.firstIndex { $0 === card }
        page.go(to: rows[lit.map { ($0 + offset + rows.count) % rows.count } ?? (offset > 0 ? 0 : rows.count - 1)])
    }

    /// The folded groups' keys, from their lines.
    private static func keys(_ lines: String) -> Set<String> {
        Set(lines.split(separator: "\n").map(String.init))
    }

    /// A section label, as in a macOS sidebar: smaller than the title, with room above. A click
    /// folds or unfolds its rows; a folded group keeps its label and count.
    private func label(_ text: String, _ count: Int, _ key: String, open: Bool, id: String) -> some View {
        Button {
            var keys = Self.keys(folded)
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
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityIdentifier(id)
        .padding(.horizontal, 8).padding(.top, 12)
    }

    /// Under its workspace's name, line 2 holds only the tab.
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
