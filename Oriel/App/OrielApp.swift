import HerdrKit
import SwiftUI

@main
struct OrielApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor private var delegate: AppDelegate
        private var settings = AppSettings()

        init() {
            SwipeRouter.install()
            Latency.shared.install()
            // Windows, not window tabs: no tab bar or tab menu items of AppKit's own.
            NSWindow.allowsAutomaticWindowTabbing = false
            // Before any surface exists, so none starts at libghostty's default size.
            PaneTerminal.setFontSize(settings.fontSize)
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
            // 90 % of the screen, centered (user, phase 29: 1200 × 760 was small on a large screen), at least
            // 1200 × 760 and at most the screen; a zoom fills the screen. A larger window AppKit shrank to fit came
            // back at its full size on a zoom, past the screen's edges (CI's 1024 pt screen). A restored window keeps
            // its frame.
            .defaultWindowPlacement { _, context in
                let screen = context.defaultDisplay.visibleRect.size
                let size = { (side: CGFloat, least: CGFloat) in min(side, max(least, side * 0.9)) }
                return WindowPlacement(.center, size: CGSize(width: size(screen.width, 1200),
                                                             height: size(screen.height, 760)))
            }
            .windowIdealSize(.maximum)
            // Content never grows the window (the title-bar tabs would, when the sidebar hides).
            .windowResizability(.contentMinSize)
            .commands { AppCommands() }
            // A folder dropped on the Dock icon opens a workspace (AppDelegate), not a window.
            .handlesExternalEvents(matching: [])
            .onChange(of: settings.fontSize) { PaneTerminal.setFontSize(settings.fontSize) }
            // A floated pane (D50). Its main window saves and opens it, so SwiftUI does not restore it.
            WindowGroup(id: "float", for: Floating.self) { $floating in
                if let floating {
                    FloatingWindow(floating: floating)
                }
            }
            .windowToolbarStyle(.unifiedCompact)
            // Until FloatReader sets a new one's frame from its main window.
            .defaultSize(width: 720, height: 460)
            .windowResizability(.contentMinSize)
            .restorationBehavior(.disabled)
            // Its scene's own File items (Close on ⌘W) came back over the main window's: ⌘W closed the main window.
            .commandsRemoved()
            // Nor does it take a folder dropped on the Dock icon: it opened an empty floating window.
            .handlesExternalEvents(matching: [])
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
        /// The window's machine's id (D43).
        @SceneStorage("machine") private var savedMachine = ""
        /// Each page's selected workspace and tabs, as JSON.
        @SceneStorage("selection") private var savedSelection = ""
        @SceneStorage("sidebar") private var sidebar = true
        @SceneStorage("sidebarWidth") private var sidebarWidth = 240.0
        /// The sidebar shows the Agents view instead of the workspaces.
        @SceneStorage("agents") private var agents = false
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Group {
                if let page = pages.current {
                    WindowContent(pages: pages, page: page, sidebar: $sidebar, agents: $agents,
                                  sidebarWidth: $sidebarWidth)
                }
            }
            .task {
                let opening = WindowPages.opening
                WindowPages.opening = nil
                await restore(opening?.machine)
                // Closed while it restored: nothing of it may stay.
                if Task.isCancelled {
                    pages.closed()
                } else {
                    pages.opened()
                    for page in pages.list {
                        for id in page.floating.keys {
                            openWindow(id: "float", value: Floating(session: page.id, terminalID: id))
                        }
                    }
                    // A machine just added connects now, asking what ssh asks in this window.
                    if opening?.connect == true, let store = pages.current?.store {
                        await store.connect(in: pages)
                    }
                }
            }
            .onChange(of: pages.list.map(\.id)) { savedPages = $1.joined(separator: " ") }
            .onChange(of: pages.current?.id) { savedPage = $1 ?? "" }
            .onChange(of: pages.machine.id) { savedMachine = $1 }
            .onChange(of: selection) { savedSelection = $1 }
            // Git status for the page in view of a visible window: now and every 10 s (D67).
            .task(id: scenePhase == .active ? pages.current?.id : nil) {
                pages.visible = scenePhase == .active
                guard pages.visible, let store = pages.current?.store else { return }
                repeat {
                    await store.updateGit(all: true)
                } while await (try? Task.sleep(for: .seconds(10))) != nil
            }
        }

        /// Each page's selection, for `savedSelection`; sorted keys, so the same selection is the same text.
        private var selection: String {
            let pages = Dictionary(uniqueKeysWithValues: pages.list.map { page in
                (page.id, Selection(workspace: page.selectedWorkspaceID, tabs: page.selectedTabIDs,
                                    floating: page.floating))
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
                page.floating = saved.floating ?? [:]
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
            /// The floated panes (D50); nil in a selection saved before them.
            var floating: [String: Bool]?
        }

        /// The machine: `opening`, else `-machine <id>`, else the saved one. Pages: `-session`, else the saved ones
        /// that still run, else `default` (`-defaultSession` for tests); This Mac's first page starts when stopped.
        /// Never another session by itself.
        private func restore(_ opening: Machine?) async {
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
            let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            let argument = arguments["session"] as? String
            let id = arguments["machine"] as? String ?? savedMachine
            let machine = opening ?? MachineList.shared.machine(id)
            if let machine {
                pages.machine = machine
            }
            // A removed machine's window opens This Mac's `default`: its saved pages were the remote's sessions.
            let removed = machine == nil && !id.isEmpty
            // A test run (`-defaultSession`) shares the developer's saved windows: it restores only throwaway sessions.
            let test = UserDefaults.standard.string(forKey: "defaultSession")
            let saved = argument == nil && !removed ? savedPages.split(separator: " ").map(String.init)
                .filter { test == nil || $0.hasPrefix("oriel-e2e-") } : []
            if !saved.isEmpty {
                let client: any Multiplexer = await HerdrClient(session: saved[0], exec: pages.machine.exec())
                // A machine that does not answer (a remote one that needs a password) keeps every page: each shows
                // why.
                let running = await (try? client.sessions())?.filter(\.running).map(\.name)
                guard !Task.isCancelled else { return }
                for name in saved where running?.contains(name) ?? true {
                    pages.open(name)
                }
                if let page = pages.list.first(where: { $0.id == savedPage }) {
                    pages.show(page)
                }
            }
            if pages.list.isEmpty {
                pages.open(argument ?? test ?? "default", start: !pages.machine.isRemote)
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
        /// The one floating panel open: the workspace menu, the palette, Open Session or Keyboard Shortcuts.
        @State private var panel: Panel?
        @State private var workspaceButtonX: CGFloat = 0
        @State private var fullScreen = false
        @State private var lightsOff = 0
        /// The window's content height, for the palette's list.
        @State private var height: CGFloat = 0
        private var settings = AppSettings()
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let style = settings.style, appearance = settings.appearance
            let look = Look(style: style, dark: colorScheme == .dark)
            let commands = CommandList(pages: pages, palette: open(.palette), sidebar: $sidebar, agents: $agents,
                                       openSession: open(.openSession), shortcuts: open(.shortcuts),
                                       settings: settings)
            // The strip's and the sidebar's 4 pt top room (for the cards' strokes) lies under the title row, so the
            // cards start at its bottom edge, as in Rex; the row stays on top for its clicks and window drags.
            VStack(spacing: -4) {
                TitleBar(
                    pages: pages,
                    page: page,
                    fullScreen: fullScreen,
                    sidebar: $sidebar,
                    sidebarWidth: sidebarWidth,
                    agents: $agents,
                    palette: open(.palette),
                    workspaceMenu: open(.workspaces),
                    openSession: open(.openSession),
                    workspaceButtonX: $workspaceButtonX,
                )
                .zIndex(1)
                HStack(spacing: 0) {
                    if pages.overview {
                        Overview(pages: pages, leading: sidebar ? sidebarWidth - gap : 0)
                    } else {
                        if sidebar {
                            // As in Rex, the cards start at the sidebar's width: its handle lies over the strip's 8 pt
                            // gap.
                            Sidebar(pages: pages, agents: agents, width: $sidebarWidth) { panel = .openSession }
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
            }
            // Rex's collapse time, for the title row too (tabs over the cards); the toggle and ⌃⌘S only flip the value.
            .animation(reduceMotion && !Animation.forceMotion ? nil : .easeInOut(duration: 0.3), value: sidebar)
            .hoverPanelHost()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .overlay {
                if panel == .workspaces {
                    WorkspaceMenu(pages: pages, page: page, open: open(.workspaces)) { panel = .openSession }
                        .padding(.leading, workspaceButtonX)
                        .padding(.top, TitleBar.height)
                        .floatingPanel(open: open(.workspaces), alignment: .topLeading)
                }
                if panel == .openSession {
                    OpenSession(pages: pages, open: open(.openSession))
                        .padding(.top, 96).floatingPanel(open: open(.openSession), alignment: .top)
                }
                if panel == .palette {
                    Palette(pages: pages, page: page, commands: commands, open: open(.palette), height: height)
                        .padding(.top, 96).floatingPanel(open: open(.palette), alignment: .top)
                }
                if panel == .shortcuts {
                    Shortcuts(commands: commands.all).floatingPanel(open: open(.shortcuts), alignment: .center)
                }
            }
            .modifier(CloseDialog(page: page))
            .overlay {
                if let machine = pages.hostDialog {
                    HostDialog(pages: pages, machine: machine).dialog()
                }
                // A new question gets a new field.
                if let question = pages.question {
                    AskDialog(question: question, machine: pages.machine).id(question.id).dialog()
                }
            }
            .environment(\.look, look)
            .testValue("window.machine", "Machine", pages.machine.name)
            .testValue("window.look", "Appearance", "\(style.rawValue) \(look.dark ? "dark" : "light")")
            // The links a test ⌘-clicked (`-recordLinks YES`).
            .testValue("app.links", "Links", Links.shared.recorded.joined(separator: " "),
                       shown: UserDefaults.standard.bool(forKey: "recordLinks"))
            .testValue("app.latency", "Latency", Latency.shared.recorded.joined(separator: "; "), shown: Latency.isOn)
            .testValue(
                "overview.motion",
                "Overview Motion",
                "\(MiniTerminal.Mini.most)",
                shown: TerminalHost.Host.record,
            )
            .onChange(of: panel, initial: true) { pages.panelOpen = panel != nil }
            // The sidebar and the Agents view count as drawn changes too (phase 29).
            .onChange(of: "\(panel.map { "\($0)" } ?? "") \(sidebar) \(agents)", initial: true) {
                Latency.shared.panel = $1
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
            .background(WindowReader(pages: pages, fullScreen: $fullScreen, lightsOff: $lightsOff))
            .testValue("window.lights", "Traffic Lights Off", "\(lightsOff)",
                       shown: UserDefaults.standard.bool(forKey: "recordLights"))
            .navigationTitle(page.selectedTab.map { "\(page.titleText($0)) - \(page.store.title)" } ?? page.store.name)
            // Every window, sheet and menu, and the terminals' palettes, follow the app's appearance.
            .onChange(of: appearance, initial: true) {
                NSApp.appearance = switch appearance {
                case .auto: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
            .menuBar(commands)
            // The workspace menu belongs to the collapsed sidebar's button.
            .onChange(of: sidebar) {
                if sidebar, panel == .workspaces {
                    panel = nil
                }
            }
            // A closed panel gives the keys back.
            .onChange(of: panel == nil) { _, closed in
                if closed {
                    page.focusKeyboardCard()
                }
            }
            .onChange(of: page.shownTerminals) { pages.showTerminals() }
        }

        enum Panel {
            case workspaces, palette, openSession, shortcuts
        }

        /// Whether this panel is the open one; opening it closes the other.
        private func open(_ which: Panel) -> Binding<Bool> {
            Binding { panel == which } set: { panel = $0 ? which : panel == which ? nil : panel }
        }
    }

    /// Glass: the desktop blurred behind the window, under the look's tint. Classic: the look's opaque color.
    struct WindowBackground: View {
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
