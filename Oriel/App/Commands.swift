#if os(macOS)
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
        }

        let section: Section
        let title: String
        var key: KeyboardShortcut?
        var enabled = true
        /// A choice: whether it is the current one (a checkmark).
        var checked: Bool?
        let action: () -> Void
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
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            let list = list
            CommandGroup(replacing: .newItem) { items(list, .file) }
            // ⌘W closes the keyboard card, ⇧⌘W the window (design: keyboard).
            CommandGroup(replacing: .saveItem) { items(list, .close) }
            CommandGroup(after: .sidebar) {
                items(list, .view)
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
                Command(section: .close, title: "Close Pane", key: .init("w"), enabled: page?.keyboardPane != nil) {
                    if let page, let pane = page.keyboardPane {
                        Task { await page.store.close(pane: pane.id) }
                    }
                },
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
                Command(section: .view, title: "Zoom Pane", key: .init(.return, modifiers: [.command, .shift]),
                        enabled: page?.keyboardPane != nil, action: {
                            guard let page else { return }
                            if let zoomed = page.zoomedPaneID, page.store.pane(zoomed)?.tabID == page.selectedTab?.id {
                                page.zoom(zoomed)
                            } else if let pane = page.keyboardPane {
                                page.zoom(pane.id)
                            }
                        }),
            ] + [Appearance.auto, .light, .dark].map { value in
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
                Command(section: .size, title: "Smaller", key: .init("-"), enabled: fontSize > PaneTerminal.fontSizes
                    .lowerBound) { PaneTerminal.stepFontSize(-1) },
                Command(
                    section: .size,
                    title: "Actual Size",
                    key: .init("0"),
                    enabled: fontSize != PaneTerminal.fontSize,
                ) {
                    fontSize = PaneTerminal.fontSize
                },
                Command(section: .tabSteps, title: "Show Previous Tab", key: .init("[", modifiers: [.command, .shift]),
                        enabled: tabs.count > 1) { page?.step(-1) },
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

        private func items(_ list: [Command], _ section: Command.Section) -> some View {
            ForEach(Array(list.filter { $0.section == section }.enumerated()), id: \.offset) { _, command in
                Group {
                    if let checked = command.checked {
                        Toggle(command.title, isOn: Binding { checked } set: { _ in command.action() })
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
