#if os(macOS)
    import SwiftUI

    extension FocusedValues {
        /// The window's store, for the menu commands.
        @Entry var store: Binding<HostStore>?
        @Entry var palette: Binding<Bool>?
        @Entry var sidebar: Binding<Bool>?
        /// The store for the tab commands; nil while the session list is open.
        @Entry var tabs: HostStore?
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
        @FocusedBinding(\.store) private var store
        @FocusedBinding(\.palette) private var palette
        @FocusedBinding(\.sidebar) private var sidebar
        @FocusedValue(\.tabs) private var tabStore
        @AppStorage("appearance") private var appearance = Appearance.dark
        @AppStorage("interfaceStyle") private var style = InterfaceStyle.glass
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize

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
            let tabs = tabStore?.selectedWorkspace?.tabs ?? []
            return [
                Command(section: .file, title: "New Tab", key: .init("t"), enabled: store?.selectedWorkspace != nil) {
                    Task { await store?.newTab() }
                },
                Command(section: .file, title: "New Session", key: .init("n", modifiers: [.command, .shift]),
                        enabled: store != nil, action: {
                            if let sessions = store?.sessions {
                                store = HostStore(session: sessions.newName, start: true)
                            }
                        }),
                Command(section: .close, title: "Close Pane", key: .init("w"), enabled: store?.keyboardPane != nil) {
                    if let store, let pane = store.keyboardPane {
                        Task { await store.close(pane: pane.id) }
                    }
                },
                Command(section: .close, title: "Close Window", key: .init("w", modifiers: [.command, .shift])) {
                    NSApp.keyWindow?.performClose(nil)
                },
                Command(section: .view, title: "Toggle Sidebar", key: .init("s", modifiers: [.command, .control]),
                        enabled: sidebar != nil) { sidebar?.toggle() },
                Command(section: .view, title: "Command Palette", key: .init("k"), enabled: palette != nil) {
                    palette?.toggle()
                },
                Command(section: .view, title: "Zoom Pane", key: .init(.return, modifiers: [.command, .shift]),
                        enabled: store?.keyboardPane != nil, action: {
                            guard let store else { return }
                            if let zoomed = store.zoomedPaneID, store.pane(zoomed)?.tabID == store.selectedTab?.id {
                                store.zoom(zoomed)
                            } else if let pane = store.keyboardPane {
                                store.zoom(pane.id)
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
                        enabled: tabs.count > 1) { tabStore?.step(-1) },
                Command(section: .tabSteps, title: "Show Next Tab", key: .init("]", modifiers: [.command, .shift]),
                        enabled: tabs.count > 1) { tabStore?.step(1) },
            ] + tabs.prefix(9).enumerated().map { index, tab in
                Command(section: .tabs, title: tabStore?.titleText(tab) ?? tab.label,
                        key: KeyboardShortcut(KeyEquivalent(Character("\(index + 1)"))), action: {
                            // The workspace when the key is pressed: the menu may be older than a workspace switch.
                            if let workspace = tabStore?.selectedWorkspace, workspace.tabs.indices.contains(index) {
                                workspace.selectedTabID = workspace.tabs[index].id
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
