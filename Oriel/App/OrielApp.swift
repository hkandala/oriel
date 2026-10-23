import HerdrKit
import SwiftUI

@main
struct OrielApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor private var delegate: AppDelegate
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize

        init() {
            SwipeRouter.install()
            // Windows, not window tabs: no tab bar or tab menu items of AppKit's own.
            NSWindow.allowsAutomaticWindowTabbing = false
            // Before any surface exists, so none starts at libghostty's default size.
            PaneTerminal.setFontSize(fontSize)
            // Second shortcuts (⇧⌘P, ⌃⇥, ⌃⇧⇥, ⌘=) run their first's menu item. A monitor sees them before any view:
            // an invisible button's shortcut kept its first action (phase 11). A disabled item lets the key go on.
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { KeyboardShortcut.second(event) } ? nil : event
            }
        }
    #endif

    var body: some Scene {
        #if os(macOS)
            WindowGroup(id: "main") {
                ContentView()
            }
            .windowToolbarStyle(.unifiedCompact)
            .defaultSize(width: 1200, height: 760)
            // Content never grows the window (the title-bar tabs would, when the sidebar hides).
            .windowResizability(.contentMinSize)
            .commands { AppCommands() }
            .onChange(of: fontSize) { PaneTerminal.setFontSize(fontSize) }
        #else
            WindowGroup {
                ContentUnavailableView("Oriel for iOS is coming", systemImage: "iphone")
            }
        #endif
    }
}

#if os(macOS)
    struct ContentView: View {
        @State private var pages = WindowPages()
        /// The open pages' names and the one in view (D43), for a window macOS restores.
        @SceneStorage("pages") private var savedPages = ""
        @SceneStorage("page") private var savedPage = ""
        /// Each page's selected workspace and tabs, as JSON.
        @SceneStorage("selection") private var savedSelection = ""
        @SceneStorage("sidebar") private var sidebar = true
        @SceneStorage("sidebarWidth") private var sidebarWidth = 240.0
        /// The sidebar shows the Agents view instead of the workspaces.
        @SceneStorage("agents") private var agents = false
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Group {
                if let page = pages.current {
                    WindowContent(pages: pages, page: page, sidebar: $sidebar, agents: $agents,
                                  sidebarWidth: $sidebarWidth)
                }
            }
            .task {
                await restore()
                // Closed while it restored: nothing of it may stay.
                if Task.isCancelled {
                    pages.closed()
                } else {
                    pages.opened()
                }
            }
            .onChange(of: pages.list.map(\.id)) { savedPages = $1.joined(separator: " ") }
            .onChange(of: pages.current?.id) { savedPage = $1 ?? "" }
            .onChange(of: selection) { savedSelection = $1 }
            // Git status for the page in view of a visible window: now and every 10 s (D67).
            .task(id: scenePhase == .active ? pages.current?.id : nil) {
                // At once for every page, not in a cancelled task's late cleanup.
                let active = scenePhase == .active
                for page in pages.list {
                    page.store.showsGit = active && page === pages.current
                }
                guard active, let store = pages.current?.store else { return }
                repeat {
                    await store.updateGit(all: true)
                } while await (try? Task.sleep(for: .seconds(10))) != nil
            }
        }

        /// Each page's selection, for `savedSelection`; sorted keys, so the same selection is the same text.
        private var selection: String {
            let pages = Dictionary(uniqueKeysWithValues: pages.list.map { page in
                (page.id, Selection(workspace: page.selectedWorkspaceID, tabs: page.selectedTabIDs))
            })
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return (try? encoder.encode(pages)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }

        /// Each page's saved selection; an id that is gone falls back to herdr's focus on the next snapshot.
        private func restoreSelection() {
            let selection = (try? JSONDecoder().decode([String: Selection].self, from: Data(savedSelection.utf8))) ??
                [:]
            for page in pages.list {
                guard let saved = selection[page.id] else { continue }
                page.selectedWorkspaceID = saved.workspace
                page.selectedTabIDs = saved.tabs
                // A store another window has loaded settles now; a new one on its first snapshot.
                if page.store.state == .live {
                    page.settle()
                }
            }
        }

        private struct Selection: Codable {
            var workspace: String?
            var tabs: [String: String]
        }

        /// `-session` on the command line if given, else the restored window's pages that still run, else
        /// `default`; the first page is started when it is stopped. Never another session by itself.
        private func restore() async {
            guard pages.list.isEmpty else { return }
            // A window macOS restores gets its scene storage a moment after it first shows; a restored window always
            // saved its pages.
            if AppDelegate.restoring {
                for _ in 0 ..< 50 where savedPages.isEmpty {
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            // Closed meanwhile: no session may start for it.
            guard !Task.isCancelled else { return }
            // A run against a throwaway session must open only it.
            let argument = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["session"]
                as? String
            let saved = argument == nil ? savedPages.split(separator: " ").map(String.init) : []
            if !saved.isEmpty {
                let client: any Multiplexer = await HerdrClient(session: saved[0], exec: exec.value)
                let running = await Set((try? client.sessions())?.filter(\.running).map(\.name) ?? [])
                guard !Task.isCancelled else { return }
                for name in saved where running.contains(name) {
                    pages.open(name)
                }
                if let page = pages.list.first(where: { $0.id == savedPage }) {
                    pages.show(page)
                }
            }
            if pages.list.isEmpty {
                pages.open(argument ?? "default", start: true)
            }
            restoreSelection()
            pages.showTerminals() // The restored tab streams now, not at the next snapshot.
        }
    }

    /// The window once it has a page: the title row, the sidebar and the page's selected workspace.
    private struct WindowContent: View {
        let pages: WindowPages
        let page: Page
        @Binding var sidebar: Bool
        @Binding var agents: Bool
        @Binding var sidebarWidth: Double
        /// The one floating panel open: the workspace menu or the palette.
        @State private var panel: Panel?
        @State private var openingSession = false
        @State private var workspaceButtonX: CGFloat = 0
        @State private var fullScreen = false
        /// The window's content height, for the palette's list.
        @State private var height: CGFloat = 0
        private var settings = AppSettings()
        @Environment(\.openWindow) private var openWindow
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let style = settings.style, appearance = settings.appearance
            let look = Look(style: style, dark: colorScheme == .dark)
            let commands = CommandList(pages: pages, palette: open(.palette), sidebar: $sidebar, agents: $agents,
                                       openSession: $openingSession, openWindow: openWindow, settings: settings)
            let store = page.store
            // The strip's and the sidebar's 4 pt top room (for the cards' strokes) lies under the title row, so the
            // cards start at its bottom edge, as in Rex; the row stays on top for its clicks and window drags.
            VStack(spacing: -4) {
                TitleBar(page: page, fullScreen: fullScreen, sidebar: $sidebar, sidebarWidth: sidebarWidth,
                         agents: $agents, palette: open(.palette), workspaceMenu: open(.workspaces),
                         workspaceButtonX: $workspaceButtonX)
                    .zIndex(1)
                HStack(spacing: 0) {
                    if sidebar {
                        // As in Rex, the cards start at the sidebar's width: its handle lies over the strip's 8 pt gap.
                        Sidebar(pages: pages, agents: agents, width: $sidebarWidth) { openingSession = true }
                            .padding(.bottom, gap)
                            // Rex's page header and first row sit 3 pt lower than the strip's 4 pt room.
                            .padding(.top, 7)
                            .padding(.trailing, -gap)
                            .zIndex(1)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Detail(pages: pages, page: page)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Rex's collapse time, for the title row too (tabs over the cards); the toggle and ⌃⌘S only flip the value.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sidebar)
            .hoverPanelHost()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .overlay {
                if panel == .workspaces {
                    WorkspaceMenu(pages: pages, page: page, open: open(.workspaces)) { openingSession = true }
                        .padding(.leading, workspaceButtonX)
                        .padding(.top, TitleBar.height)
                        .floatingPanel(open: open(.workspaces), alignment: .topLeading)
                }
                if panel == .palette {
                    Palette(pages: pages, page: page, commands: commands, open: open(.palette), height: height)
                        .padding(.top, 96).floatingPanel(
                            open: open(.palette),
                            alignment: .top,
                        )
                }
            }
            .sheet(isPresented: $openingSession) { OpenSession(pages: pages) }
            .confirmationDialog(dialog?.title ?? "", isPresented: Binding { store.closing != nil } set: {
                if !$0 {
                    store.closing = nil
                }
            }, titleVisibility: .visible, presenting: store.closing) { close in
                Button(close.button, role: .destructive) {
                    Task { await store.close(close) }
                }
            } message: { _ in
                Text(dialog?.message ?? "")
            }
            .environment(\.look, look)
            // A text leaf: SwiftUI exposes no value on a container or a plain element. One point, so accessibility
            // hit tests still find the cards and buttons.
            .background(alignment: .topLeading) {
                Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel("Appearance").accessibilityIdentifier("window.look")
                    // Last for VoiceOver: it is for tests more than for people.
                    .accessibilitySortPriority(-1)
                    .accessibilityValue("\(style.rawValue) \(look.dark ? "dark" : "light")")
            }
            .modifier(AgentsWatch(pages: pages, page: page))
            // The title bar row takes the hidden title bar's line.
            .ignoresSafeArea(edges: .top)
            .containerBackground(for: .window) { WindowBackground(look: look) }
            .toolbar { ToolbarSpacer(.flexible) }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // In full screen the empty toolbar would cover the title row; it shows on hover only.
            .windowToolbarFullScreenVisibility(.onHover)
            .background(WindowReader(pages: pages, fullScreen: $fullScreen))
            .navigationTitle(page.selectedTab.map { "\(page.titleText($0)) - \(page.id)" } ?? HostStore.name(page.id))
            // Every window, sheet and menu, and the terminals' palettes, follow the app's appearance.
            .onChange(of: appearance, initial: true) {
                NSApp.appearance = switch appearance {
                case .auto: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
            .focusedSceneValue(\.commands, commands)
            // The workspace menu belongs to the collapsed sidebar's button.
            .onChange(of: sidebar) {
                if sidebar, panel == .workspaces {
                    panel = nil
                }
            }
            // A closed panel or sheet gives the keys back.
            .onChange(of: panel == nil && !openingSession) { _, closed in
                if closed {
                    page.focusKeyboardCard()
                }
            }
            .onChange(of: page.shownTerminals) { pages.showTerminals() }
        }

        enum Panel {
            case workspaces, palette
        }

        /// Whether this panel is the open one; opening it closes the other.
        private func open(_ which: Panel) -> Binding<Bool> {
            Binding { panel == which } set: { panel = $0 ? which : panel == which ? nil : panel }
        }

        /// The close dialog's text (design D41): a close ends processes on every device and cannot be undone.
        private var dialog: (title: String, message: String)? {
            let store = page.store
            let end = " will end, here and in every herdr client. This cannot be undone."
            let panes = { (tabs: [String]) in store.panes.count { tabs.contains($0.tabID) } }
            let them = { (count: Int) in
                "\(count == 1 ? "pane" : "\(count) panes") and everything running in \(count == 1 ? "it" : "them")"
            }
            switch store.closing {
            case let .tab(id):
                let tab = store.workspaces.flatMap(\.tabs).first { $0.id == id }
                return ("Close the tab “\(tab.map(page.titleText) ?? id)”?", "Its " + them(panes([id])) + end)
            case let .otherTabs(others):
                return ("Close \(others.count == 1 ? "the other tab" : "the \(others.count) other tabs")?",
                        "Their " + them(panes(others)) + end)
            case let .pane(id, program):
                return ("Close “\(store.pane(id)?.title ?? id)”?", "\(program) is running in it" + end)
            case let .workspace(id):
                let workspace = store.workspaces.first { $0.id == id }
                let worktrees = store.worktrees(of: id)
                let tabs = ([workspace].compactMap(\.self) + worktrees).flatMap(\.tabs).map(\.id)
                let also = worktrees.isEmpty ? "" : worktrees.count == 1 ? " and its worktree’s workspace"
                    : " and its \(worktrees.count) worktrees’ workspaces"
                return ("Close the workspace “\(workspace?.label ?? id)”\(also)?",
                        "\(tabs.count == 1 ? "Its tab" : "Its \(tabs.count) tabs"), " + them(panes(tabs)) + end)
            case nil:
                return nil
            }
        }
    }

    private extension HostStore.Close {
        var button: String {
            switch self {
            case .pane: "Close Pane"
            case .tab: "Close Tab"
            case .otherTabs: "Close Tabs"
            case .workspace: "Close Workspace"
            }
        }
    }

    /// Glass: the desktop blurred behind the window, under the look's tint. Classic: the look's opaque color.
    private struct WindowBackground: View {
        let look: Look

        var body: some View {
            if look.style == .glass {
                Frosted().overlay(look.backdrop.blendMode(BlendMode.overlay)).overlay(look.window)
            } else {
                look.window
            }
        }
    }

    /// The Glass window's blur of the desktop. SwiftUI's materials blur only what is inside the window.
    private struct Frosted: NSViewRepresentable {
        func makeNSView(context _: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.blendingMode = .behindWindow
            view.material = .hudWindow
            // Blurred in an inactive window too, so the look holds.
            view.state = .active
            return view
        }

        func updateNSView(_: NSVisualEffectView, context _: Context) {}
    }

#endif
