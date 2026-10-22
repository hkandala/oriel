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
            .commands {
                TabCommands()
                ActionCommands()
            }
            .onChange(of: fontSize) { PaneTerminal.setFontSize(fontSize) }
        #else
            WindowGroup {
                ContentUnavailableView("Oriel for iOS is coming", systemImage: "iphone")
            }
        #endif
    }
}

#if os(macOS)
    /// One for the app's life: it reads the login shell's environment once.
    private let exec = Task { await ProcessExec() }

    struct ContentView: View {
        /// `-session <name>` on the command line lands in UserDefaults.
        @State private var store = HostStore(session: UserDefaults.standard.string(forKey: "session") ?? "default")
        @State private var sidebar = true
        @State private var picking = false
        @State private var fullScreen = false
        @State private var palette = false
        @AppStorage("appearance") private var appearance = Appearance.dark
        @AppStorage("interfaceStyle") private var style = InterfaceStyle.glass
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let look = Look(style: style, dark: colorScheme == .dark)
            VStack(spacing: 0) {
                TitleBar(store: store, fullScreen: fullScreen, sidebar: $sidebar, picking: $picking, palette: $palette)
                HStack(spacing: 0) {
                    if sidebar {
                        Sidebar(store: store)
                            .padding([.leading, .bottom], gap)
                            .padding(.top, 4)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Detail(store: $store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay {
                if picking {
                    SessionList(store: $store, open: $picking)
                        .padding(.leading, TitleBar.inset(fullScreen: fullScreen) + TitleBar.picker)
                        .padding(.top, TitleBar.height + 4)
                        .floatingPanel(open: $picking, alignment: .topLeading)
                }
                if palette {
                    Palette(store: $store, open: $palette).padding(.top, 96).floatingPanel(
                        open: $palette,
                        alignment: .top,
                    )
                }
            }
            .confirmationDialog(dialog?.title ?? "", isPresented: Binding { store.closing != nil } set: {
                if !$0 {
                    store.closing = nil
                }
            }, titleVisibility: .visible, presenting: store.closing) { close in
                Button(close.isTab ? "Close Tab" : "Close Pane", role: .destructive) {
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
            .navigationTitle(store.selectedTab?.label ?? HostStore.name(store.session))
            // Every window, sheet and menu, and the terminals' palettes, follow the app's appearance.
            .onChange(of: appearance, initial: true) {
                NSApp.appearance = switch appearance {
                case .auto: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
            .focusedSceneValue(\.store, $store)
            // The menu's ⌘1…⌘9 tabs step aside while the session list has its own ⌘1…⌘9.
            .focusedSceneValue(\.tabs, picking ? nil : store)
            .focusedSceneValue(\.palette, $palette)
            // The palette and the session list never show together; a closed palette gives the keys back.
            .onChange(of: palette) {
                if palette {
                    picking = false
                } else {
                    store.focusKeyboardCard()
                }
            }
            // A new store (session switch) cancels the old one's run, which drops its client.
            .task(id: ObjectIdentifier(store)) { await store.run(exec: exec.value) }
            // Here, not in the detail: a failed or empty session must release its terminals too.
            .onChange(of: store.shownTerminals) { store.showTerminals() }
        }

        /// The close dialog's text (design D41): a close ends processes on every device and cannot be undone.
        private var dialog: (title: String, message: String)? {
            switch store.closing {
            case let .tab(id):
                let tab = store.workspaces.flatMap(\.tabs).first { $0.id == id }
                let count = store.panes.count { $0.tabID == id }
                return ("Close the tab “\(tab?.label ?? id)”?",
                        "Its \(count == 1 ? "pane" : "\(count) panes") and everything running in "
                            + "\(count == 1 ? "it" : "them") will end, here and in every herdr client. "
                            + "This cannot be undone.")
            case let .pane(id, program):
                return ("Close “\(store.pane(id)?.title ?? id)”?",
                        "\(program) is running in it and will end, here and in every herdr client. "
                            + "This cannot be undone.")
            case nil:
                return nil
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

    /// The selected workspace's tabs, or why there is nothing to show.
    private struct Detail: View {
        @Binding var store: HostStore

        var body: some View {
            switch store.state {
            case .connecting:
                ProgressView("Connecting to \(HostStore.name(store.session))")
            case .live:
                if let workspace = store.selectedWorkspace {
                    Strip(workspace: workspace, store: store)
                        .overlay(alignment: .bottom) {
                            if let notice = store.notice {
                                Text(notice).padding(8).glassEffect().padding(gap * 2)
                                    .accessibilityIdentifier("detail.notice")
                            }
                        }
                } else {
                    message("No workspaces", "Create one in herdr:",
                            "herdr --session \(store.session) workspace create")
                }
            case .failed(.notFound):
                message("herdr is not installed", "Install it in a terminal:",
                        "curl -fsSL https://herdr.dev/install.sh | sh")
            case let .failed(.unsupported(text)):
                message("herdr is too old", text + ". Update it in a terminal:", "herdr update")
            case .failed where !store.isRunning:
                message("\(HostStore.name(store.session)) is not running", "Start it here, or in a terminal:",
                        "herdr --session \(store.session) server", start: true)
            case let .failed(error):
                message("No answer from herdr", error.localizedDescription, nil)
            }
        }

        /// What is wrong and the command that fixes it; a stopped session also gets a Start button (design D47).
        private func message(_ title: String, _ text: String, _ command: String?, start: Bool = false) -> some View {
            ContentUnavailableView {
                Label(title, systemImage: "terminal")
            } description: {
                Text(text)
                if let command {
                    Text(command).monospaced().textSelection(.enabled)
                }
            } actions: {
                if start {
                    Button("Start \(store.session)") { store = HostStore(session: store.session, start: true) }
                        .accessibilityIdentifier("detail.start")
                }
            }
        }
    }
#endif
