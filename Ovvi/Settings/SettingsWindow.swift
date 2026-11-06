import SwiftUI

/// The Settings window's pages (ui/settings), in the sidebar's order.
enum SettingsPage: String, CaseIterable, Hashable {
    case general, appearance, terminal, agents, machines, plugins, privacy

    var title: String {
        rawValue.capitalized
    }

    /// Its sidebar row's SF Symbol, drawn white on a grey tile (`SettingsIcon`).
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .terminal: "apple.terminal"
        case .agents: "sparkles"
        case .machines: "desktopcomputer"
        case .plugins: Registry.missing
        case .privacy: "hand.raised"
        }
    }
}

/// A page under Machines or Plugins: a machine's by its id, a plugin's by its id.
enum SettingsDetail: Hashable {
    case machine(String), plugin(String)
}

/// Where the window is: the page, the detail page over it, and the row a search pick rings for a second.
@MainActor @Observable
final class SettingsRoute {
    static let shared = SettingsRoute()
    var page: SettingsPage? = .general
    var path: [SettingsDetail] = []
    var ring: String?

    /// Opens the window at a page, and a detail page on it.
    func open(_ page: SettingsPage, _ detail: SettingsDetail? = nil) {
        self.page = page
        path = detail.map { [$0] } ?? []
        WindowPages.openWindow?(id: "settings")
    }
}

/// Ovvi ▸ Settings… (⌘,): a sidebar of pages, as macOS System Settings, each page a grouped form.
struct SettingsWindow: View {
    @State private var search = ""
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        @Bindable var route = SettingsRoute.shared
        NavigationSplitView {
            // A pick in the sidebar leaves any detail page; a search pick and `open` set both.
            List(selection: Binding { route.page } set: { route.page = $0
                route.path = []
            }) {
                if search.isEmpty {
                    ForEach(SettingsPage.allCases, id: \.self) { page in
                        SettingsSidebarRow(page: page)
                    }
                } else {
                    ForEach(SettingsSearch.matches(search)) { row in
                        Button {
                            route.page = row.page
                            route.path = row.detail.map { [$0] } ?? []
                            route.ring = row.id
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title)
                                    Text(row.place ?? row.page.title).font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                SettingsIcon(page: row.page)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.search.\(row.id)")
                    }
                }
            }
            .overlay {
                if !search.isEmpty, SettingsSearch.matches(search).isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .sidebar)
            // As System Settings: the sidebar always shows.
            .toolbar(removing: .sidebarToggle)
            .accessibilityIdentifier("settings.sidebar")
            .navigationSplitViewColumnWidth(215)
        } detail: {
            NavigationStack(path: $route.path) {
                SettingsPageView(page: route.page ?? .general)
                    .navigationDestination(for: SettingsDetail.self) { detail in
                        switch detail {
                        case let .machine(id): MachinePage(id: id)
                        case let .plugin(id): PluginPage(id: id)
                        }
                    }
            }
        }
        // As System Settings: a set width, the height the user's.
        .frame(width: 715).frame(minHeight: 400)
        .environment(\.look, Look(style: settings.style, dark: colorScheme == .dark,
                                  contrast: colorSchemeContrast == .increased))
    }
}

private struct SettingsSidebarRow: View {
    let page: SettingsPage

    var body: some View {
        Label { Text(page.title) } icon: { SettingsIcon(page: page) }
            .tag(page)
            .accessibilityIdentifier("settings.page.\(page.rawValue)")
    }
}

/// The sidebar page's form.
private struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        Group {
            switch page {
            case .general: GeneralPage()
            case .appearance: AppearancePage()
            case .terminal: TerminalPage()
            case .agents: AgentsPage()
            case .machines: MachinesPage()
            case .plugins: PluginsPage()
            case .privacy: PrivacyPage()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(page.title)
        // A toolbar item, so the window has a toolbar as System Settings: with none (the sidebar toggle is gone), the
        // window had a bare title bar, its traffic lights in the corner and its corners square. A pushed page has
        // its Back button.
        .toolbar { ToolbarSpacer(.fixed) }
        .scrollsToRing()
    }
}

/// Scrolls a page to a search pick's row, then lets the ring go after a second. Each page has its own: a plugin's page
/// is pushed over the sidebar's page, whose proxy cannot reach it.
private struct RingScroll: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.task(id: SettingsRoute.shared.ring) {
                guard let ring = SettingsRoute.shared.ring else { return }
                // After the page's first layout: its rows are there to scroll to.
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(ring, anchor: .center) }
                try? await Task.sleep(for: .seconds(1))
                if SettingsRoute.shared.ring == ring {
                    SettingsRoute.shared.ring = nil
                }
            }
        }
    }
}

extension View {
    /// A page that a search pick scrolls (`settingsRow`).
    func scrollsToRing() -> some View {
        modifier(RingScroll())
    }

    /// A row a search can find: scrolled to and ringed for a second when picked.
    func settingsRow(_ id: String) -> some View {
        modifier(SettingsRow(id: id))
    }
}

private struct SettingsRow: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.id(id).background {
            if SettingsRoute.shared.ring == id {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).padding(-6)
            }
        }
    }
}

/// The rows a search finds: each setting's title and more words, its page, and its row.
struct SettingsSearch: Identifiable {
    let id: String, title: String, page: SettingsPage
    var words = ""
    var detail: SettingsDetail?
    /// Where it is, when not just its page: "Plugins › Git".
    var place: String?

    static let app = [
        SettingsSearch(id: "general.open-at-login", title: "Open at login", page: .general,
                       words: "startup launch login items"),
        SettingsSearch(id: "general.follow-mouse", title: "Focus follows mouse", page: .general, words: "pane hover"),
        SettingsSearch(id: "general.shortcuts", title: "Keyboard shortcuts", page: .general, words: "keys help"),
        SettingsSearch(id: "appearance.appearance", title: "Appearance", page: .appearance,
                       words: "auto light dark theme mode"),
        SettingsSearch(id: "appearance.style", title: "Interface style", page: .appearance,
                       words: "glass classic"),
        SettingsSearch(id: "appearance.font-size", title: "Text size", page: .appearance, words: "font bigger"),
        SettingsSearch(id: "terminal.font", title: "Font", page: .terminal, words: "typeface monospaced"),
        SettingsSearch(id: "terminal.cursor", title: "Cursor", page: .terminal, words: "block bar underline"),
        SettingsSearch(id: "terminal.blink", title: "Blink the cursor", page: .terminal),
        SettingsSearch(id: "terminal.option", title: "Option key", page: .terminal, words: "meta alt emacs"),
        SettingsSearch(id: "terminal.copy", title: "Copy text when you select it", page: .terminal,
                       words: "clipboard selection"),
        SettingsSearch(id: "agents.view", title: "Open new agents in", page: .agents, words: "chat terminal tui"),
        SettingsSearch(id: "agents.settle", title: "Settle idle agents after", page: .agents,
                       words: "agents view settled idle hours"),
        SettingsSearch(id: "agents.new-pane", title: "Agents in New Pane", page: .agents,
                       words: "arguments flags claude codex pi opencode"),
        SettingsSearch(id: "agents.needs-you", title: "When an agent needs you", page: .agents,
                       words: "notifications"),
        SettingsSearch(id: "agents.finished", title: "When an agent finishes", page: .agents,
                       words: "notifications done"),
        SettingsSearch(id: "agents.from-agents", title: "When an agent sends one", page: .agents,
                       words: "notifications notify"),
        SettingsSearch(id: "machines.list", title: "Machines", page: .machines, words: "remote ssh host add"),
        SettingsSearch(id: "privacy.websites", title: "Approved websites", page: .privacy,
                       words: "browser sites privacy allowlist add"),
    ]

    /// The rows whose title, words or page hold every typed word.
    static func matches(_ text: String) -> [SettingsSearch] {
        let typed = text.lowercased().split(separator: " ")
        return (app + PluginsPage.searchRows).filter { row in
            let words = "\(row.title) \(row.words) \(row.place ?? row.page.title)".lowercased()
            return typed.allSatisfy { words.contains($0) }
        }
    }
}

/// A pushed page's first card, as System Settings' detail pages: a large icon, the name (and a version), a line or two
/// under it, and the page's own small buttons on the trailing edge.
struct SettingsHeader<Icon: View, Actions: View>: View {
    let title: String
    var note: String?
    var lines: [String] = []
    @ViewBuilder var icon: Icon
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    if let note {
                        Text(note).foregroundStyle(.secondary)
                    }
                }
                // A description wraps; the last line, a source or a target, keeps its ends.
                let shown = lines.filter { !$0.isEmpty }
                ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                    let last = index == shown.count - 1
                    Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(last ? 1 : 2)
                        .truncationMode(last ? .middle : .tail)
                }
            }
            Spacer(minLength: 8)
            actions.controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

extension SettingsHeader where Actions == EmptyView {
    init(title: String, note: String? = nil, lines: [String] = [], @ViewBuilder icon: () -> Icon) {
        self.init(title: title, note: note, lines: lines, icon: icon, actions: { EmptyView() })
    }
}
