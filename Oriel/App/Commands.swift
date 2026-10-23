import SwiftUI

/// Shortcuts written in more than one place: the command list, the chrome buttons' tooltips, the second keys.
extension KeyboardShortcut {
    static let newTab = KeyboardShortcut("t")
    static let openSession = KeyboardShortcut("n", modifiers: [.command, .shift])
    static let toggleSidebar = KeyboardShortcut("s", modifiers: [.command, .control])
    static let palette = KeyboardShortcut("k")
    static let splitRight = KeyboardShortcut("d")
    static let splitDown = KeyboardShortcut("d", modifiers: [.command, .shift])
    static let zoom = KeyboardShortcut(.return, modifiers: [.command, .shift])
    static let closePane = KeyboardShortcut("w")
    static let previousTab = KeyboardShortcut("[", modifiers: [.command, .shift])
    static let nextTab = KeyboardShortcut("]", modifiers: [.command, .shift])
    static let bigger = KeyboardShortcut("+")
    static let findNext = KeyboardShortcut("g")

    /// A command's second shortcut runs the menu item of its first (OrielApp's key monitor); the menu shows the first.
    static let seconds: [(second: KeyboardShortcut, first: KeyboardShortcut)] = [
        (KeyboardShortcut("p", modifiers: [.command, .shift]), .palette),
        (KeyboardShortcut(.tab, modifiers: [.control, .shift]), .previousTab),
        (KeyboardShortcut(.tab, modifiers: .control), .nextTab),
        (KeyboardShortcut("="), .bigger),
    ]

    /// As the menu bar draws it: "⇧⌘N".
    var glyphs: String {
        let modifiers: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keys: [Character: String] = [
            KeyEquivalent.return.character: "↩", KeyEquivalent.tab.character: "⇥",
            KeyEquivalent.leftArrow.character: "←", KeyEquivalent.rightArrow.character: "→",
            KeyEquivalent.upArrow.character: "↑", KeyEquivalent.downArrow.character: "↓",
            KeyEquivalent.pageUp.character: "⇞", KeyEquivalent.pageDown.character: "⇟",
        ]
        return modifiers.filter { self.modifiers.contains($0.0) }.map(\.1).joined()
            + (keys[key.character] ?? String(key.character).uppercased())
    }
}

#if os(macOS)
    import HerdrKit

    extension KeyboardShortcut {
        var modifierFlags: NSEvent.ModifierFlags {
            let pairs: [(EventModifiers, NSEvent.ModifierFlags)] = [
                (.command, .command), (.shift, .shift), (.option, .option), (.control, .control),
            ]
            return NSEvent.ModifierFlags(pairs.filter { modifiers.contains($0.0) }.map(\.1))
        }

        /// The second shortcut's key went down: runs the menu item of its first, when enabled. Whether it did.
        @MainActor static func second(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Tab by its key code: with Shift its character is backtab.
            let key = event.keyCode == 48 ? KeyEquivalent.tab.character : event.charactersIgnoringModifiers?
                .lowercased()
                .first
            guard let first = seconds
                .first(where: { $0.second.modifierFlags == flags && $0.second.key.character == key })?.first,
                let item = NSApp.mainMenu?.item(first), item.isEnabled, let menu = item.menu,
                // ⌃⇥ in a text field (the palette, a rename) stays the field's: the tabs behind it must not move.
                key != KeyEquivalent.tab.character || !(NSApp.keyWindow?.firstResponder is NSText),
                // Not behind a sheet (the open panel, Open Session).
                NSApp.keyWindow?.sheetParent == nil else { return false }
            // Not `performKeyEquivalent` with a made-up event: AppKit did not match "]" with ⇧⌘ to ⇧⌘].
            menu.performActionForItem(at: menu.index(of: item))
            return true
        }
    }

    private extension NSMenu {
        func item(_ shortcut: KeyboardShortcut) -> NSMenuItem? {
            for item in items {
                if item.keyEquivalent == String(shortcut.key.character),
                   item.keyEquivalentModifierMask == shortcut.modifierFlags
                {
                    return item
                }
                if let found = item.submenu?.item(shortcut) {
                    return found
                }
            }
            return nil
        }
    }

    extension FocusedValues {
        /// The key window's commands, for the menu bar.
        @Entry var commands: CommandList?
    }

    /// The menu bar's settings (D62), for the command list.
    struct AppSettings: DynamicProperty {
        @AppStorage("appearance") var appearance = Appearance.dark
        @AppStorage("interfaceStyle") var style = InterfaceStyle.glass
        @AppStorage("fontSize") var fontSize = PaneTerminal.fontSize
        @AppStorage("fadeInactivePanes") var fade = true
        @AppStorage("focusFollowsMouse") var followMouse = false
    }

    /// One command (D48). The menu bar and the palette read the one list of them (`CommandList`).
    struct Command {
        /// Its group in the menu bar, divided from the others; in the menu bar's order, which the palette follows too.
        enum Section: CaseIterable {
            case file, close, edit, view
            /// View ▸ Pane's setting, first.
            case paneSetting
            /// View ▸ Pane, and the card header's context menu.
            case pane, paneMove
            /// View ▸ Pane, keys only.
            case paneKeys
            case size, tabSteps, pages, tabs
            /// The palette only.
            case palette
        }

        let section: Section
        let title: String
        /// The palette row's id when the title may repeat (a move's target tabs); else the title.
        var id: String?
        var key: KeyboardShortcut?
        /// The palette row's SF Symbol.
        var symbol: String?
        /// More words the palette's filter matches.
        var keywords = ""
        var enabled = true
        /// On or off, or a choice that is the current one (a checkmark).
        var checked: Bool?
        /// A setting: the palette's title says what it does now ("Turn On Focus Follows Mouse").
        var setting = false
        /// A submenu instead of an action; a sub-page in the palette.
        var menu: [Command] = []
        /// The palette's sub-page tries a highlighted row on the window (Appearance, Interface Style).
        var previews = false
        /// The palette's name page: the current name, and what Enter does with the field.
        var name: (current: String, save: (String) async -> Void)?
        var action: () -> Void = {}
    }

    /// The menu bar, drawn from the key window's command list; the shortcuts work wherever the keyboard is.
    struct AppCommands: Commands {
        @FocusedValue(\.commands) private var commands
        @Environment(\.openWindow) private var openWindow
        private var settings = AppSettings()

        var body: some Commands {
            // With no window: New Window and the settings.
            let opener = Self.keep(openWindow)
            let list = (commands ?? CommandList(openWindow: opener, settings: settings)).all
            CommandGroup(replacing: .newItem) { items(list, .file) }
            // ⌘W closes the keyboard card, ⇧⌘W the window (design: keyboard).
            CommandGroup(replacing: .saveItem) { items(list, .close) }
            CommandGroup(after: .pasteboard) { items(list, .edit) }
            CommandGroup(after: .sidebar) {
                items(list, .view)
                Menu("Pane") { CommandItems(commands: list, sections: [.paneSetting, .pane, .paneMove, .paneKeys]) }
                Divider()
                items(list, .size)
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                CommandItems(commands: list, sections: [.tabSteps, .pages, .tabs])
            }
        }

        /// The menu bar's commands exist with no window: the app delegate opens one through this for a Dock drop.
        private static func keep(_ openWindow: OpenWindowAction) -> OpenWindowAction {
            WindowPages.openWindow = openWindow
            return openWindow
        }

        private func items(_ list: [Command], _ section: Command.Section) -> some View {
            CommandItems(commands: list, sections: [section])
        }
    }

    /// Menu items for commands: a toggle for a choice, a submenu, else a button. With sections, those sections'
    /// commands in that order, divided.
    struct CommandItems: View {
        let commands: [Command]
        var sections: [Command.Section]?

        var body: some View {
            let shown = sections.map { sections in
                sections.flatMap { section in commands.filter { $0.section == section } }
            } ?? commands
            ForEach(Array(shown.enumerated()), id: \.offset) { index, command in
                if index > 0, sections != nil, shown[index - 1].section != command.section {
                    Divider()
                }
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
