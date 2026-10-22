import HerdrKit
import SwiftUI

@main
struct OrielApp: App {
    #if os(macOS)
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize

        init() {
            SwipeRouter.install()
            // One window; no tab bar or tab menu items of AppKit's own.
            NSWindow.allowsAutomaticWindowTabbing = false
            // Before any surface exists, so none starts at libghostty's default size.
            PaneTerminal.setFontSize(fontSize)
            // ⌘= is View ▸ Bigger's second key (the menu shows ⌘+). A monitor sees it before any view: an invisible
            // button's shortcut kept its first action. At 32 the key goes on and beeps, as the disabled Bigger does.
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection([.command, .control, .option]) == .command,
                      event.charactersIgnoringModifiers == "=",
                      UserDefaults.standard.object(forKey: "fontSize") as? Int ?? PaneTerminal.fontSize
                      < PaneTerminal.fontSizes.upperBound else { return event }
                MainActor.assumeIsolated { PaneTerminal.stepFontSize(1) }
                return nil
            }
        }
    #endif

    var body: some Scene {
        #if os(macOS)
            Window("Oriel", id: "main") {
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
        /// Per window (phase 16 opens more).
        @SceneStorage("sidebar") private var sidebar = true
        @SceneStorage("sidebarWidth") private var sidebarWidth = 240.0
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Group {
                if let page = pages.current {
                    WindowContent(pages: pages, page: page, sidebar: $sidebar, sidebarWidth: $sidebarWidth)
                }
            }
            .task { await restore() }
            .onChange(of: pages.list.map(\.id)) { savedPages = $1.joined(separator: " ") }
            .onChange(of: pages.current?.id) { savedPage = $1 ?? "" }
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

        /// The pages a restored window had that still run; else the first page: `-session` (in UserDefaults from
        /// the command line), else `default`, started when it is stopped. Never another session by itself.
        private func restore() async {
            guard pages.list.isEmpty else { return }
            // `-session` wins over a restored window: a run against a throwaway session opens only it.
            let argument = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["session"]
            let saved = argument == nil ? savedPages.split(separator: " ").map(String.init) : []
            if !saved.isEmpty {
                let client: any Multiplexer = await HerdrClient(session: saved[0], exec: exec.value)
                let running = await Set((try? client.sessions())?.filter(\.running).map(\.name) ?? [])
                for name in saved where running.contains(name) {
                    pages.open(name)
                }
                if let page = pages.list.first(where: { $0.id == savedPage }) {
                    pages.show(page)
                }
            }
            if pages.list.isEmpty {
                pages.open(UserDefaults.standard.string(forKey: "session") ?? "default", start: true)
            }
        }
    }

    /// The window once it has a page: the title row, the sidebar and the page's selected workspace.
    private struct WindowContent: View {
        let pages: WindowPages
        let page: Page
        @Binding var sidebar: Bool
        @Binding var sidebarWidth: Double
        /// The one floating panel open: the workspace menu or the palette.
        @State private var panel: Panel?
        @State private var openingSession = false
        @State private var workspaceButtonX: CGFloat = 0
        @State private var fullScreen = false
        @AppStorage("appearance") private var appearance = Appearance.dark
        @AppStorage("interfaceStyle") private var style = InterfaceStyle.glass
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let look = Look(style: style, dark: colorScheme == .dark)
            let store = page.store
            VStack(spacing: 0) {
                TitleBar(page: page, fullScreen: fullScreen, sidebar: $sidebar, palette: open(.palette),
                         workspaceMenu: open(.workspaces), workspaceButtonX: $workspaceButtonX)
                HStack(spacing: 0) {
                    if sidebar {
                        Sidebar(pages: pages, width: $sidebarWidth) { openingSession = true }
                            .padding([.leading, .bottom], gap)
                            .padding(.top, 4)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Detail(page: page)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Rex's collapse time; the toggle and ⌃⌘S only flip the value.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sidebar)
            }
            .overlay {
                if panel == .workspaces {
                    WorkspaceMenu(pages: pages, page: page, open: open(.workspaces)) { openingSession = true }
                        .padding(.leading, workspaceButtonX)
                        .padding(.top, TitleBar.height)
                        .floatingPanel(open: open(.workspaces), alignment: .topLeading)
                }
                if panel == .palette {
                    Palette(pages: pages, page: page, open: open(.palette)).padding(.top, 96).floatingPanel(
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
            // The title bar row takes the hidden title bar's line.
            .ignoresSafeArea(edges: .top)
            .containerBackground(for: .window) { WindowBackground(look: look) }
            .toolbar { ToolbarSpacer(.flexible) }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // In full screen the empty toolbar would cover the title row; it shows on hover only.
            .windowToolbarFullScreenVisibility(.onHover)
            .background(FullScreenReader(fullScreen: $fullScreen))
            .navigationTitle(page.selectedTab.map { "\(page.titleText($0)) - \(page.id)" } ?? HostStore.name(page.id))
            // Every window, sheet and menu, and the terminals' palettes, follow the app's appearance.
            .onChange(of: appearance, initial: true) {
                NSApp.appearance = switch appearance {
                case .auto: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
            .focusedSceneValue(\.page, page)
            .focusedSceneValue(\.palette, open(.palette))
            .focusedSceneValue(\.sidebar, $sidebar)
            .focusedSceneValue(\.openSession, $openingSession)
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

    /// Whether this view's window is in full screen (or on its way in), from its style and its notifications.
    private struct FullScreenReader: NSViewRepresentable {
        @Binding var fullScreen: Bool

        func makeNSView(context _: Context) -> Reader {
            Reader()
        }

        func updateNSView(_ reader: Reader, context _: Context) {
            reader.changed = { fullScreen = $0 }
        }

        final class Reader: NSView {
            var changed: (Bool) -> Void = { _ in }
            private var observers: [NSObjectProtocol] = []

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                guard let window else { return }
                // A window macOS restores in full screen keeps AppKit's empty title bar over the title row (the
                // toolbar's on-hover full screen look holds only when the user enters). Its frame still comes back
                // (frame autosave); full screen does not.
                window.isRestorable = false
                let notifications = [NSWindow.willEnterFullScreenNotification: true,
                                     NSWindow.willExitFullScreenNotification: false]
                for (name, value) in notifications {
                    let center = NotificationCenter.default
                    observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.changed(value) }
                    })
                }
                // After SwiftUI's update, which may not change state.
                let full = window.styleMask.contains(.fullScreen)
                DispatchQueue.main.async { [weak self] in self?.changed(full) }
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

    /// The page's selected workspace's tabs, or why there is nothing to show.
    private struct Detail: View {
        let page: Page

        var body: some View {
            let store = page.store
            switch store.state {
            case .connecting:
                ProgressView("Connecting to \(HostStore.name(store.session))")
            case .live:
                if let workspace = page.selectedWorkspace {
                    Strip(workspace: workspace, page: page)
                        .overlay(alignment: .bottom) {
                            if let notice = store.notice {
                                Text(notice).padding(8).glassEffect().padding(gap * 2)
                                    .accessibilityIdentifier("detail.notice")
                            }
                        }
                } else {
                    NewWorkspaceButton(page: page)
                }
            case .failed(.notFound):
                message("herdr is not installed", "Install it in a terminal:",
                        "curl -fsSL https://herdr.dev/install.sh | sh")
            case let .failed(.unsupported(text)):
                message("herdr is too old", text + ". Update it in a terminal:", "herdr update")
            case .failed where !store.isRunning:
                message("\(store.session) is not running", "Start it to see its workspaces.", nil, start: true)
            case let .failed(error):
                message("No answer from herdr", error.localizedDescription, nil)
            }
        }

        /// What is wrong and the command that fixes it; a stopped session gets a Start button instead (design D47).
        private func message(_ title: String, _ text: String, _ command: String?, start: Bool = false) -> some View {
            ContentUnavailableView {
                Label(title, systemImage: "terminal")
            } description: {
                Text(text)
                // Why a start failed.
                if let notice = page.store.notice {
                    Text(notice).accessibilityIdentifier("detail.notice")
                }
                if let command {
                    Text(command).monospaced().textSelection(.enabled)
                }
            } actions: {
                if start {
                    Button("Start \(page.store.session)") { Task { await page.store.start() } }
                        .accessibilityIdentifier("detail.start")
                }
            }
        }
    }
#endif
