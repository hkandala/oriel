#if os(macOS)
    import HerdrKit
    import SwiftUI

    extension FocusedValues {
        /// The window's page in view, for the menu commands.
        @Entry var page: Page?
        @Entry var palette: Binding<Bool>?
        @Entry var sidebar: Binding<Bool>?
        @Entry var agents: Binding<Bool>?
        @Entry var openSession: Binding<Bool>?
    }

    /// One command (D48). The menu bar reads the one list of them (`AppCommands.list`); the palette will too.
    struct Command {
        /// Its group in the menu bar; groups are divided from each other.
        enum Section {
            case file, close, view, appearance, interfaceStyle, size, tabSteps, tabs
            /// View ▸ Pane, and the card header's context menu.
            case pane, paneMove
            /// View ▸ Pane, keys only.
            case paneKeys
        }

        let section: Section
        let title: String
        var key: KeyboardShortcut?
        var enabled = true
        /// A choice: whether it is the current one (a checkmark).
        var checked: Bool?
        /// A submenu instead of an action.
        var menu: [Command] = []
        var action: () -> Void = {}
    }

    /// The menu bar, drawn from the command list; the shortcuts work wherever the keyboard is.
    struct AppCommands: Commands {
        @FocusedValue(\.page) private var page
        @FocusedBinding(\.palette) private var palette
        @FocusedValue(\.sidebar) private var sidebar
        @FocusedValue(\.agents) private var agents
        @FocusedBinding(\.openSession) private var openSession
        @AppStorage("appearance") private var appearance = Appearance.dark
        @AppStorage("interfaceStyle") private var style = InterfaceStyle.glass
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize
        @AppStorage("fadeInactivePanes") private var fade = true
        @AppStorage("focusFollowsMouse") private var followMouse = false
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            let list = list
            CommandGroup(replacing: .newItem) { items(list, .file) }
            // ⌘W closes the keyboard card, ⇧⌘W the window (design: keyboard).
            CommandGroup(replacing: .saveItem) { items(list, .close) }
            CommandGroup(after: .sidebar) {
                items(list, .view)
                Menu("Pane") {
                    items(list, .pane)
                    Divider()
                    items(list, .paneMove)
                    Divider()
                    items(list, .paneKeys)
                }
                Divider()
                Menu("Appearance") { items(list, .appearance) }
                Menu("Interface Style") { items(list, .interfaceStyle) }
                Divider()
                items(list, .size)
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                items(list, .tabSteps)
                Divider()
                items(list, .tabs)
            }
        }

        var list: [Command] {
            let tabs = page?.selectedWorkspace?.tabs ?? []
            return [
                Command(section: .file, title: "New Window", key: .init("n")) { openWindow(id: "main") },
                Command(section: .file, title: "New Tab", key: .init("t"), enabled: page?.selectedWorkspace != nil) {
                    Task { await page?.newTab() }
                },
                Command(section: .file, title: "Open Session…", key: .init("n", modifiers: [.command, .shift]),
                        enabled: openSession != nil) { openSession = true },
                Command(section: .close, title: "Close Window", key: .init("w", modifiers: [.command, .shift])) {
                    NSApp.keyWindow?.performClose(nil)
                },
                Command(section: .view, title: "Toggle Sidebar", key: .init("s", modifiers: [.command, .control]),
                        enabled: sidebar != nil) { sidebar?.wrappedValue.toggle() },
                Command(section: .view, title: "Show Agents", key: .init("."), enabled: agents != nil && sidebar != nil,
                        checked: agents?.wrappedValue == true && sidebar?.wrappedValue == true, action: {
                            if let agents, let sidebar {
                                toggleAgents(agents, sidebar)
                            }
                        }),
                Command(section: .view, title: "Command Palette", key: .init("k"), enabled: palette != nil) {
                    palette?.toggle()
                },
                Command(section: .view, title: "Fade Inactive Panes", checked: fade) { fade.toggle() },
            ] + Self.pane(page) { [page] in page?.keyboardPane } + paneKeys + [Appearance.auto, .light, .dark]
                .map { value in
                    Command(section: .appearance, title: value.rawValue.capitalized, checked: appearance == value) {
                        appearance = value
                    }
                } + [InterfaceStyle.glass, .classic].map { value in
                    Command(section: .interfaceStyle, title: value.rawValue.capitalized, checked: style == value) {
                        style = value
                    }
                } + [
                    // The text size (design: theme and accessibility); OrielApp's key monitor takes ⌘=.
                    Command(section: .size, title: "Bigger", key: .init("+"), enabled: fontSize < PaneTerminal.fontSizes
                        .upperBound) { PaneTerminal.stepFontSize(1) },
                    Command(
                        section: .size,
                        title: "Smaller",
                        key: .init("-"),
                        enabled: fontSize > PaneTerminal.fontSizes
                            .lowerBound,
                    ) { PaneTerminal.stepFontSize(-1) },
                    Command(
                        section: .size,
                        title: "Actual Size",
                        key: .init("0"),
                        enabled: fontSize != PaneTerminal.fontSize,
                    ) {
                        fontSize = PaneTerminal.fontSize
                    },
                    Command(
                        section: .tabSteps,
                        title: "Show Previous Tab",
                        key: .init("[", modifiers: [.command, .shift]),
                        enabled: tabs.count > 1,
                    ) { page?.step(-1) },
                    Command(section: .tabSteps, title: "Show Next Tab", key: .init("]", modifiers: [.command, .shift]),
                            enabled: tabs.count > 1) { page?.step(1) },
                ] + tabs.prefix(9).enumerated().map { index, tab in
                    Command(section: .tabs, title: page?.titleText(tab) ?? tab.label,
                            key: KeyboardShortcut(KeyEquivalent(Character("\(index + 1)"))), action: {
                                // The workspace when the key is pressed: the menu may be older than a workspace switch.
                                if let page, let workspace = page.selectedWorkspace,
                                   workspace.tabs.indices.contains(index)
                                {
                                    page.select(workspace, tab: workspace.tabs[index].id)
                                }
                            })
                }
        }

        /// The pane's actions (D48), for View ▸ Pane on the keyboard card and the card header's context menu. Close
        /// Pane is in the File menu. Actions ask `target` for the pane when they run: the menu bar may be older than
        /// the last keyboard move.
        static func pane(_ page: Page?, _ target: @escaping @MainActor () -> HostStore.Pane?) -> [Command] {
            guard let page, let pane = target() else {
                return ["Split Right", "Split Down", "Split Left", "Split Up", "Zoom Pane"]
                    .map { Command(section: .pane, title: $0, enabled: false) }
                    + ["Move to New Tab", "Move to Tab", "Move to New Workspace", "Rename Pane…"]
                    .map { Command(section: .paneMove, title: $0, enabled: false) }
                    + [Command(section: .close, title: "Close Pane", key: .init("w"), enabled: false)]
            }
            let store = page.store, workspace = store.workspace(of: pane.tabID), zoomed = page.zoomedPaneID == pane.id
            func act(_ title: String, _ key: KeyboardShortcut? = nil, _ section: Command.Section = .pane,
                     _ run: @escaping (HostStore.Pane) async -> Void) -> Command
            {
                Command(section: section, title: title, key: key) {
                    if let pane = target() {
                        Task { await run(pane) }
                    }
                }
            }
            return [
                act("Split Right", .init("d")) { await page.split($0.id, .right) },
                act("Split Down", .init("d", modifiers: [.command, .shift])) { await page.split($0.id, .down) },
                act("Split Left") { await page.split($0.id, .right, before: true) },
                act("Split Up") { await page.split($0.id, .down, before: true) },
                Command(section: .pane, title: zoomed ? "Restore Pane" : "Zoom Pane",
                        key: .init(.return, modifiers: [.command, .shift]),
                        enabled: zoomed || store.panes.count { $0.tabID == pane.tabID } > 1, action: {
                            if let pane = target() {
                                page.zoom(pane.id)
                            }
                        }),
                act("Move to New Tab", nil, .paneMove) { pane in
                    if let workspace = store.workspace(of: pane.tabID) {
                        await page.move(pane, to: .newTab(workspaceID: workspace.id))
                    }
                },
                // herdr refuses a move into the pane's own tab.
                Command(section: .paneMove, title: "Move to Tab", enabled: (workspace?.tabs.count ?? 0) > 1,
                        menu: (workspace?.tabs ?? []).filter { $0.id != pane.tabID }.map { other in
                            act(page.titleText(other)) { await page.move($0, to: .tab(other.id)) }
                        }),
                act("Move to New Workspace", nil, .paneMove) { await page.move($0, to: .newWorkspace) },
                act("Rename Pane…", nil, .paneMove) { page.renamingPaneID = $0.id },
                act("Close Pane", .init("w"), .close) { await store.close(pane: $0.id) },
            ]
        }

        /// Keys that move the keyboard, the pane or a divider; and Focus Follows Mouse.
        private var paneKeys: [Command] {
            let page = page, enabled = page?.keyboardPane != nil, tab = page?.selectedTab
            let arrows: [(Heading, KeyEquivalent)] = [
                (.left, .leftArrow), (.right, .rightArrow), (.up, .upArrow), (.down, .downArrow),
            ]
            func each(_ title: String, _ modifiers: EventModifiers,
                      _ act: @escaping (Page, HostStore.Pane, Heading) async -> Void) -> [Command]
            {
                arrows.map { heading, key in
                    Command(section: .paneKeys, title: "\(title) \(heading.rawValue.capitalized)",
                            key: .init(key, modifiers: modifiers), enabled: enabled, action: {
                                if let page, let pane = page.keyboardPane {
                                    Task { await act(page, pane, heading) }
                                }
                            })
                }
            }
            // Even when it looks even: the menu may be older than the tab's last change.
            let balance = Command(section: .paneKeys, title: "Balance Splits",
                                  key: .init("=", modifiers: [.command, .control]), enabled: tab != nil, action: {
                                      if let page, let tab = page.selectedTab {
                                          Task { await page.store.balance(tab) }
                                      }
                                  })
            return [balance] +
                each("Select Pane", [.command, .option]) { page, _, heading in await page.moveKeyboard(heading) }
                + [
                    Command(section: .paneKeys, title: "Select Previous Pane", key: .init("["), enabled: enabled) {
                        page?.stepCard(-1)
                    },
                    Command(section: .paneKeys, title: "Select Next Pane", key: .init("]"), enabled: enabled) {
                        page?.stepCard(1)
                    },
                ]
                + each("Move Pane", [.command, .option, .shift]) { await $0.store.swap($1.id, $2) }
                + each("Resize Pane", [.command, .control]) { await $0.store.resize($1.id, $2) }
                + [Command(section: .paneKeys, title: "Focus Follows Mouse", checked: followMouse) {
                    followMouse.toggle()
                }]
        }

        private func items(_ list: [Command], _ section: Command.Section) -> some View {
            CommandItems(commands: list.filter { $0.section == section })
        }
    }

    /// Menu items for commands: a toggle for a choice, a submenu, else a button.
    struct CommandItems: View {
        let commands: [Command]

        var body: some View {
            ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                Group {
                    if let checked = command.checked {
                        Toggle(command.title, isOn: Binding { checked } set: { _ in command.action() })
                    } else if !command.menu.isEmpty {
                        Menu(command.title) { CommandItems(commands: command.menu) }
                    } else {
                        Button(command.title, action: command.action)
                    }
                }
                .keyboardShortcut(command.key)
                .disabled(!command.enabled)
            }
        }
    }
#endif
