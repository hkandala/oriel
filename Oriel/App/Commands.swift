#if os(macOS)
    import SwiftUI

    extension FocusedValues {
        /// The window's store, for the menu commands.
        @Entry var store: Binding<HostStore>?
        @Entry var palette: Binding<Bool>?
        /// The store for the tab commands; nil while the session list is open.
        @Entry var tabs: HostStore?
    }

    /// The menu bar's actions on the window's store; the shortcuts work wherever the keyboard is.
    struct ActionCommands: Commands {
        @FocusedBinding(\.store) private var store
        @FocusedBinding(\.palette) private var palette
        @AppStorage("appearance") private var appearance = Appearance.dark
        @AppStorage("interfaceStyle") private var style = InterfaceStyle.glass
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { Task { await store?.newTab() } }
                    .keyboardShortcut("t")
                    .disabled(store?.selectedWorkspace == nil)
                Button("New Session") {
                    if let sessions = store?.sessions {
                        store = HostStore(session: sessions.newName, start: true)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store == nil)
            }
            // ⌘W closes the keyboard card, ⇧⌘W the window (design: keyboard).
            CommandGroup(replacing: .saveItem) {
                Button("Close Pane") {
                    if let store, let pane = store.keyboardPane {
                        Task { await store.close(pane: pane.id) }
                    }
                }
                .keyboardShortcut("w")
                .disabled(store?.keyboardPane == nil)
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Command Palette") { palette?.toggle() }
                    .keyboardShortcut("k")
                    .disabled(palette == nil)
                Button("Zoom Pane") {
                    guard let store else { return }
                    if let zoomed = store.zoomedPaneID, store.pane(zoomed)?.tabID == store.selectedTab?.id {
                        store.zoom(zoomed)
                    } else if let pane = store.keyboardPane {
                        store.zoom(pane.id)
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(store?.keyboardPane == nil)
                Divider()
                Picker("Appearance", selection: $appearance) {
                    Text("Auto").tag(Appearance.auto)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                Picker("Interface Style", selection: $style) {
                    Text("Glass").tag(InterfaceStyle.glass)
                    Text("Classic").tag(InterfaceStyle.classic)
                }
                Divider()
                // The text size (design: theme and accessibility). OrielApp's key monitor takes ⌘+ and ⌘=; Bigger's
                // shortcut shows in the menu.
                Button("Bigger") { PaneTerminal.stepFontSize(1) }
                    .keyboardShortcut("+")
                    .disabled(fontSize >= PaneTerminal.fontSizes.upperBound)
                Button("Smaller") { PaneTerminal.stepFontSize(-1) }
                    .keyboardShortcut("-")
                    .disabled(fontSize <= PaneTerminal.fontSizes.lowerBound)
                Button("Actual Size") { fontSize = PaneTerminal.fontSize }
                    .keyboardShortcut("0")
                    .disabled(fontSize == PaneTerminal.fontSize)
            }
        }
    }

    /// In the Window menu: the selected workspace's tabs on ⌘1…⌘9, and ⇧⌘[ / ⇧⌘] for the one before or after.
    struct TabCommands: Commands {
        @FocusedValue(\.tabs) private var store

        var body: some Commands {
            CommandGroup(after: .windowArrangement) {
                let tabs = store?.selectedWorkspace?.tabs ?? []
                Divider()
                Button("Show Previous Tab") { store?.step(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(tabs.count < 2)
                Button("Show Next Tab") { store?.step(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(tabs.count < 2)
                Divider()
                ForEach(Array(tabs.prefix(9).enumerated()), id: \.element.id) { index, tab in
                    // The workspace when the key is pressed: the menu may be older than a workspace switch.
                    Button(tab.label) {
                        if let workspace = store?.selectedWorkspace, workspace.tabs.indices.contains(index) {
                            workspace.selectedTabID = workspace.tabs[index].id
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }
    }
#endif
