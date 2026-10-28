import HerdrKit
import SwiftUI

/// Shortcuts written in more than one place: the command list, the chrome buttons' tooltips, the second keys.
extension KeyboardShortcut {
    static let newTab = KeyboardShortcut("t")
    static let openSession = KeyboardShortcut("t", modifiers: [.command, .option])
    static let toggleSidebar = KeyboardShortcut("s", modifiers: [.command, .control])
    static let overview = KeyboardShortcut("o", modifiers: [.command, .control])
    static let palette = KeyboardShortcut("k")
    static let splitRight = KeyboardShortcut("d")
    static let splitDown = KeyboardShortcut("d", modifiers: [.command, .shift])
    static let zoom = KeyboardShortcut(.return, modifiers: [.command, .shift])
    /// Close Pane; in a floating window Detach Pane, which closes the window and puts the pane back in its tab.
    static let closePane = KeyboardShortcut("w")
    /// ⇧⌘R: ⌘R reloads a browser card.
    static let replacePane = KeyboardShortcut("r", modifiers: [.command, .shift])
    /// Close Tab; in a floating window Close Pane.
    static let closeTab = KeyboardShortcut("w", modifiers: [.command, .shift])
    static let previousTab = KeyboardShortcut("[", modifiers: [.command, .shift])
    static let nextTab = KeyboardShortcut("]", modifiers: [.command, .shift])
    static let bigger = KeyboardShortcut("+")
    static let findNext = KeyboardShortcut("g")

    /// A command's second shortcut runs its first's command (OrielApp's key monitor); the menu shows the first.
    static let seconds: [(second: KeyboardShortcut, first: KeyboardShortcut)] = [
        (KeyboardShortcut("p", modifiers: [.command, .shift]), .palette),
        (KeyboardShortcut(.tab, modifiers: [.control, .shift]), .previousTab),
        (KeyboardShortcut(.tab, modifiers: .control), .nextTab),
        (KeyboardShortcut("="), .bigger),
    ]

    /// As the menu bar draws it: "⌥⌘T".
    var glyphs: String {
        caps.joined()
    }

    /// One glyph per modifier, then the key's: ["⌥", "⌘", "T"].
    var caps: [String] {
        let modifiers: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keys: [Character: String] = [
            KeyEquivalent.return.character: "↩", KeyEquivalent.tab.character: "⇥",
            KeyEquivalent.leftArrow.character: "←", KeyEquivalent.rightArrow.character: "→",
            KeyEquivalent.upArrow.character: "↑", KeyEquivalent.downArrow.character: "↓",
        ]
        return modifiers.filter { self.modifiers.contains($0.0) }.map(\.1)
            + [keys[key.character] ?? String(key.character).uppercased()]
    }
}

extension KeyboardShortcut {
    var modifierFlags: NSEvent.ModifierFlags {
        let pairs: [(EventModifiers, NSEvent.ModifierFlags)] = [
            (.command, .command), (.shift, .shift), (.option, .option), (.control, .control),
        ]
        return NSEvent.ModifierFlags(pairs.filter { modifiers.contains($0.0) }.map(\.1))
    }

    /// The key event is this shortcut's: its modifiers, and its key with or without Shift's character (⇧⌘[ types
    /// "{"). Tab by its key code: with Shift its character is backtab.
    func matches(_ event: NSEvent) -> Bool {
        let keys = event.keyCode == 48 ? "\t"
            : (event.charactersIgnoringModifiers ?? "") + (event.characters(byApplyingModifiers: []) ?? "")
        return event.modifierFlags.intersection([.command, .shift, .option, .control]) == modifierFlags
            && keys.lowercased().contains(key.character)
    }

    /// The second shortcut's key went down in an Oriel window: runs its first's command there, when enabled, and
    /// takes the key either way. A disabled Show Next Tab (one tab) let ⌃⇥ go on to AppKit's key view loop, which
    /// stepped the panes. Whether it took the key.
    @MainActor static func second(_ event: NSEvent) -> Bool {
        guard let first = seconds.first(where: { $0.second.matches(event) })?.first,
              let commands = CommandList.keyWindow else { return false }
        // ⌃⇥ in a text field (the palette, a rename) does nothing: the tabs behind it must not move.
        if event.keyCode != 48 || !(NSApp.keyWindow?.firstResponder is NSText) {
            commands.run { $0 == first }
        }
        return true
    }
}

extension FocusedValues {
    /// The key window's commands, for the menu bar.
    @Entry var commands: CommandList?
}

extension CommandList: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.shown == rhs.shown
    }
}

extension View {
    /// The window's commands for the menu bar, again whenever what it shows of them changes. SwiftUI rebuilds the
    /// menu bar only when this value changes: `Commands` do not observe. Zoom Pane, disabled while the tab had one
    /// card, stayed so after a split, and ⇧⌘↩ did nothing. A modifier, so reading `all` re-runs only its
    /// body, not the window's.
    func menuBar(_ commands: CommandList) -> some View {
        modifier(MenuBar(commands: commands))
    }
}

private struct MenuBar: ViewModifier {
    let commands: CommandList

    func body(content: Content) -> some View {
        var commands = commands
        // What the actions act on too: an equal value keeps the old one, and its actions (another floating
        // window's pane, another page). The keyboard card, read here so a keyboard move redraws the menu.
        let page = commands.pages?.current
        commands.shown = [
            [commands.floating as Any, commands.pages.map(ObjectIdentifier.init) as Any,
             page.map(ObjectIdentifier.init) as Any].map { String(describing: $0) }.joined(separator: " "),
            page?.keyboardCard(page?.selectedTab?.id)?.id ?? "",
        ] + commands.menuBarList.map(\.shown)
        return content.focusedSceneValue(\.commands, commands).background(KeyWindowList(commands: commands))
    }
}

@MainActor
extension CommandList {
    /// The key window's commands, made when the key is pressed: the menu bar's list may still be another
    /// window's. nil without one (a sheet, no window).
    static var keyWindow: [Command]? {
        KeyWindowList.Holder.all.allObjects.first { $0.window?.isKeyWindow == true }?.commands?.menuBarList
    }
}

extension [Command] {
    /// Runs the command whose key `matches`, when enabled. Whether it ran.
    @discardableResult func run(_ matches: (KeyboardShortcut) -> Bool) -> Bool {
        guard let command = first(where: { $0.key.map(matches) == true }), command.enabled else { return false }
        command.action()
        return true
    }
}

/// The window's commands where a key finds them (`CommandList.keyWindow`).
private struct KeyWindowList: NSViewRepresentable {
    let commands: CommandList

    func makeNSView(context _: Context) -> Holder {
        let holder = Holder()
        Holder.all.add(holder)
        return holder
    }

    func updateNSView(_ holder: Holder, context _: Context) {
        holder.commands = commands
    }

    final class Holder: NSView {
        static let all = NSHashTable<Holder>.weakObjects()
        var commands: CommandList?
    }
}

/// The menu bar's settings (D62), for the command list.
struct AppSettings: DynamicProperty {
    @AppStorage("appearance") var appearance = Appearance.dark
    @AppStorage("interfaceStyle") var style = InterfaceStyle.glass
    @AppStorage("fontSize") var fontSize = PaneTerminal.fontSize
    @AppStorage("focusFollowsMouse") var followMouse = false
    /// The chat view's detail level, one for the app (ui/chat-view#detail-levels).
    @AppStorage("chatLevel") var chatLevel = ChatLevel.steps
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
        case size, tabSteps, workspaceSteps, pages, tabs, workspaces, sessions
        /// The palette only.
        case palette
        case help

        /// Its group on the Keyboard Shortcuts panel, unless the command names its own.
        var group: Group {
            switch self {
            case .edit: .edit
            case .paneSetting, .pane, .paneMove, .paneKeys: .panes
            case .tabSteps, .tabs: .tabs
            case .workspaceSteps, .workspaces: .workspaces
            case .pages, .sessions: .sessions
            case .file, .close, .view, .size, .palette, .help: .view
            }
        }
    }

    /// The Keyboard Shortcuts panel's groups, in its order.
    enum Group: String {
        case panes = "Panes", tabs = "Tabs", workspaces = "Workspaces", sessions = "Sessions", view = "View"
        case edit = "Edit"
    }

    let section: Section
    let title: String
    /// The palette row's id when the title may repeat (a move's target tabs); else the title.
    var id: String?
    var key: KeyboardShortcut?
    /// The Keyboard Shortcuts panel's group, when not its section's.
    var group: Group?
    /// The Keyboard Shortcuts panel's one row for a set of commands that differ by the key: "Select Pane" and
    /// one keycap for the keys, "←→↑↓", after the modifiers'.
    var family: (title: String, keys: String)?
    /// The palette row's SF Symbol.
    var symbol: String?
    /// A program icon's id instead of the symbol (an agent of Start Agent Here).
    var program: String?
    /// The header of its section in a submenu and a palette sub-page: a workspace's name over its tabs.
    var heading: String?
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

    /// What the menu bar shows of it.
    var shown: String {
        "\(title) \(enabled) \(String(describing: checked)) \(key?.glyphs ?? "") \(menu.map(\.shown))"
    }
}

/// The menu bar, drawn from the focused window's command list; its keys run the key window's commands
/// (`CommandList.keyWindow`), wherever the keyboard is.
struct AppCommands: Commands {
    @FocusedValue(\.commands) private var commands
    @Environment(\.openWindow) private var openWindow
    private var settings = AppSettings()

    var body: some Commands {
        // Every main window opens through it. `_ =` is no statement in a builder.
        // swiftlint:disable:next redundant_discardable_let
        let _ = (WindowPages.openWindow = openWindow)
        // A key runs the key window's command for it, whichever window's list the menu bar holds; behind a sheet,
        // none. With no window: New Window and the settings.
        let list = (commands ?? CommandList(settings: settings)).menuBarList.map { command in
            var keyed = command
            if let key = command.key {
                keyed.action = {
                    if let live = CommandList.keyWindow {
                        live.run { $0 == key }
                    } else if NSApp.keyWindow?.sheetParent == nil {
                        command.action()
                    }
                }
            }
            return keyed
        }
        CommandGroup(replacing: .appInfo) { Button("About Oriel") { openWindow(id: "about") } }
        CommandGroup(replacing: .newItem) { items(list, .file) }
        // ⌘W closes the keyboard card, ⇧⌘W the tab, ⌃⌘W the workspace, ⌥⌘W detaches the session (design: keyboard).
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
            CommandItems(commands: list, sections: [.tabSteps, .workspaceSteps, .pages, .tabs, .workspaces,
                                                    .sessions])
        }
        CommandGroup(replacing: .help) { items(list, .help) }
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
        // Each run under one heading is a section of the menu (Move Pane to Tab's workspaces).
        let starts = shown.indices.filter { $0 == 0 || shown[$0].heading != shown[$0 - 1].heading }
        ForEach(starts, id: \.self) { start in
            let run = start ..< (starts.first { $0 > start } ?? shown.count)
            if let heading = shown[start].heading {
                Section(heading) { items(shown, run) }
            } else {
                items(shown, run)
            }
        }
    }

    private func items(_ shown: [Command], _ run: Range<Int>) -> some View {
        ForEach(run, id: \.self) { index in
            let command = shown[index]
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
