import SwiftUI

/// The Settings window's pages (ui/settings), in the sidebar's order.
enum SettingsPage: String, CaseIterable, Hashable {
    case general, appearance, terminal, agents, machines, plugins, privacy

    var title: String {
        rawValue.capitalized
    }

    /// Its sidebar tile's SF Symbol; the tile's color is in `SettingsTile`.
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .terminal: "apple.terminal.fill"
        case .agents: "sparkles"
        case .machines: "server.rack"
        case .plugins: Registry.missing
        case .privacy: "hand.raised.fill"
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

    /// The app's Settings opener, kept by the menu bar (`AppCommands`) for actions outside a view.
    static var openSettings: OpenSettingsAction?

    /// Opens the window at a page, and a detail page on it.
    func open(_ page: SettingsPage, _ detail: SettingsDetail? = nil) {
        self.page = page
        path = detail.map { [$0] } ?? []
        Self.openSettings?()
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
                    ForEach(SettingsPage.shown, id: \.self) { page in
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
                                SettingsTile(page: row.page, symbol: row.page.symbol)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.search.\(row.id)")
                    }
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
        .frame(width: 715, height: 560)
        .environment(\.look, Look(style: settings.style, dark: colorScheme == .dark,
                                  contrast: colorSchemeContrast == .increased))
    }
}

@MainActor
extension SettingsPage {
    /// The pages with something in them: Privacy only with approved websites, or while it shows.
    static var shown: [SettingsPage] {
        allCases.filter { $0 != .privacy || PrivacyPage.hasItems || SettingsRoute.shared.page == .privacy }
    }
}

private struct SettingsSidebarRow: View {
    let page: SettingsPage

    var body: some View {
        Label { Text(page.title) } icon: { SettingsTile(page: page, symbol: page.symbol) }
            .badge(page == .plugins ? PluginsPage.waiting : 0)
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
                       words: "browser sites privacy"),
    ]

    /// The rows whose title, words or page hold every typed word; Privacy's only when it shows.
    static func matches(_ text: String) -> [SettingsSearch] {
        let typed = text.lowercased().split(separator: " "), shown = SettingsPage.shown
        return (app + PluginsPage.searchRows).filter { row in
            let words = "\(row.title) \(row.words) \(row.place ?? row.page.title)".lowercased()
            return shown.contains(row.page) && typed.allSatisfy { words.contains($0) }
        }
    }
}
