import HerdrKit
import SwiftUI

/// Every command of a window (D48), for its menu bar and its palette. Actions find what they act on when they
/// run: the menu bar may be older than the last selection or keyboard move.
struct CommandList {
    var pages: WindowPages?
    var palette: Binding<Bool>?
    var sidebar: Binding<Bool>?
    var agents: Binding<Bool>?
    var openSession: Binding<Bool>?
    var shortcuts: Binding<Bool>?
    let settings: AppSettings
    /// A floating window's list (D50): only what applies to it.
    var floating: Floating?
    /// What the menu bar shows and acts on, when it was made (`menuBar`).
    var shown: [String] = []

    private var tabs = true

    /// The menu bar's: Move Pane to Tab without the session's tabs. AppKit's key equivalent search walks
    /// the whole menu bar at every key (about 30 ms at 300 tabs), and each tab's new title made the menu bar again.
    /// The card's menus and the palette list them.
    var menuBarList: [Command] {
        var bar = self
        bar.tabs = false
        return bar.all
    }

    var all: [Command] {
        if let floating {
            return floatingCommands(floating)
        }
        let page = pages?.current, pages = pages, workspace = page?.selectedWorkspace, tab = page?.selectedTab
        let live = page?.store.state == .live
        let file = [
            Command(section: .file, title: "New Window", key: .init("n"), symbol: "macwindow.badge.plus") {
                WindowPages.open(machine: pages?.machine ?? .thisMac)
            },
            Command(section: .file, title: "New Tab", key: .newTab, group: .tabs, symbol: "plus.square",
                    enabled: workspace != nil) { Task { await page?.newTab() } },
            Command(section: .file, title: "New Workspace", key: .init("t", modifiers: [.command, .control]),
                    group: .workspaces, symbol: "folder.badge.plus",
                    enabled: live) { Task { await page?.newWorkspace() } },
            Command(section: .file, title: "Open Session…", key: .openSession, group: .sessions,
                    symbol: "rectangle.stack.badge.plus",
                    keywords: "create start switch", enabled: openSession != nil, action: {
                        openSession?.wrappedValue = true
                    }),
            Command(section: .file, title: "Go to Directory…", key: .init("g", modifiers: [.command, .shift]),
                    group: .edit, symbol: "folder", keywords: "cd folder path navigate",
                    enabled: page?.keyboardPane.map { $0.program?.isShell == true && $0.plugin == nil } == true,
                    action: {
                        Task { await page?.choosePath(directory: true) }
                    }),
        ]
        let close = [
            Command(section: .close, title: "Close Tab", key: .closeTab, group: .tabs, symbol: "xmark.rectangle",
                    enabled: tab != nil, action: {
                        if let page, let tab = page.selectedTab {
                            page.close(.tab(tab.id))
                        }
                    }),
            Command(section: .close, title: "Close Other Tabs", symbol: "xmark.rectangle.fill",
                    enabled: (workspace?.tabs.count ?? 0) > 1, action: {
                        if let page, let tab = page.selectedTab {
                            page.closeTabs(besides: tab.id, right: false)
                        }
                    }),
            Command(section: .close, title: "Close Tabs to the Right", symbol: "arrow.right.to.line.compact",
                    enabled: tab != nil && workspace?.tabs.last?.id != tab?.id, action: {
                        if let page, let tab = page.selectedTab {
                            page.closeTabs(besides: tab.id, right: true)
                        }
                    }),
            Command(section: .close, title: "Close Workspace", key: .init("w", modifiers: [.command, .control]),
                    group: .workspaces, symbol: "folder.badge.minus", enabled: workspace != nil, action: {
                        if let page, let workspace = page.selectedWorkspace {
                            page.close(.workspace(workspace.id))
                        }
                    }),
            Command(section: .close, title: "Detach Session", key: .init("w", modifiers: [.command, .option]),
                    group: .sessions, symbol: "rectangle.stack.badge.minus", enabled: (pages?.list.count ?? 0) > 1,
                    action: {
                        if let pages, let page = pages.current {
                            pages.close(page)
                        }
                    }),
            Command(section: .close, title: "Close Window", symbol: "xmark") { NSApp.keyWindow?.performClose(nil) },
        ]
        let find = page?.find, terminal = page?.keyboardPane.map { $0.plugin == nil } == true
        let browser = page?.keyboardPane.flatMap { page?.browser($0) }
        let edit = [
            Command(section: .edit, title: "Insert Path…", key: .init("i", modifiers: [.command, .shift]),
                    symbol: "text.insert", keywords: "file folder path",
                    enabled: terminal) { Task { await page?.choosePath(directory: false) } },
            // As in Rex, Find Previous has no key: ⇧⌘G is Go to Directory.
            Command(section: .edit, title: "Find…", key: .init("f"), symbol: "magnifyingglass",
                    keywords: "search scrollback", enabled: live && terminal) { page?.openFind() },
            Command(section: .edit, title: "Find Next", key: .findNext, symbol: "chevron.down",
                    enabled: find != nil) { Task { await page?.find?.step(1) } },
            Command(section: .edit, title: "Find Previous", symbol: "chevron.up", enabled: find != nil) {
                Task { await page?.find?.step(-1) }
            },
        ]
        return file + Self.pane(page, tabs: tabs) { [page] in page?.keyboardPane } + close + edit + Self
            .browser(browser)
            + view + paneKeys
            + palette(page) + window(page, pages)
    }

    private var view: [Command] {
        let size = settings.fontSize, sizes = PaneTerminal.fontSizes
        let current = pages?.current
        let page = current?.keyboardPane?.browser
        // A browser card with the keyboard (its page or its address field) zooms its page instead.
        func zoom(_ step: Int, else text: @escaping () -> Void) -> () -> Void {
            {
                let card = current?.keyboardPane.flatMap { $0.terminalID.flatMap { current?.terminals.built($0) } }
                if let view = BrowserView.focused ?? card?.view {
                    view.zoom(step)
                } else {
                    text()
                }
            }
        }
        return [
            Command(section: .view, title: "Command Palette", key: .palette, symbol: "command",
                    enabled: palette != nil) { palette?.wrappedValue.toggle() },
            Command(section: .help, title: "Keyboard Shortcuts", key: .init("/"), symbol: "keyboard",
                    keywords: "keys help", enabled: shortcuts != nil) { shortcuts?.wrappedValue.toggle() },
            Command(section: .view, title: "Show Agents", key: .init("."), symbol: "list.bullet.rectangle",
                    keywords: "needs you", enabled: agents != nil && sidebar != nil,
                    checked: agents?.wrappedValue == true && sidebar?.wrappedValue == true, action: {
                        if let agents, let sidebar {
                            pages?.afterOverview { toggleAgents(agents, sidebar) }
                        }
                    }),
            Command(section: .view, title: "Toggle Sidebar", key: .toggleSidebar, symbol: "sidebar.left",
                    enabled: sidebar != nil && pages?.overview != true) { sidebar?.wrappedValue.toggle() },
            Command(section: .view, title: "Show Overview", key: .overview, symbol: "square.grid.2x2",
                    keywords: "all tabs grid expose", enabled: pages?.current != nil,
                    checked: pages?.overview == true) { pages?.toggleOverview() },
            Command(section: .view, title: "Appearance", symbol: "circle.lefthalf.filled",
                    keywords: "auto light dark theme mode", menu: [Appearance.auto, .light, .dark].map { value in
                        Command(section: .view, title: value.rawValue.capitalized,
                                checked: settings.appearance == value) { settings.appearance = value }
                    }, previews: true),
            Command(section: .view, title: "Interface Style", symbol: "paintbrush", keywords: "glass classic theme",
                    menu: [InterfaceStyle.glass, .classic].map { value in
                        Command(section: .view, title: value.rawValue.capitalized,
                                checked: settings.style == value) { settings.style = value }
                    }, previews: true),
            // The text size (design: theme and accessibility); the key monitor takes ⌘=.
            Command(section: .size, title: "Increase Font Size", key: .bigger, symbol: "textformat.size.larger",
                    keywords: "bigger text", enabled: size < sizes.upperBound || page != nil,
                    action: zoom(1) { PaneTerminal.stepFontSize(1) }),
            Command(section: .size, title: "Decrease Font Size", key: .init("-"), symbol: "textformat.size.smaller",
                    keywords: "smaller text", enabled: size > sizes.lowerBound || page != nil,
                    action: zoom(-1) { PaneTerminal.stepFontSize(-1) }),
            Command(section: .size, title: "Reset Font Size", key: .init("0"), symbol: "textformat.size",
                    keywords: "actual size text", enabled: size != PaneTerminal.fontSize || page != nil,
                    action: zoom(0) { [settings] in settings.fontSize = PaneTerminal.fontSize }),
        ]
    }

    /// Sub-pages and commands the menu bar has elsewhere (the capsule and row context menus, AppKit's View menu).
    private func palette(_ page: Page?) -> [Command] {
        let tab = page?.selectedTab, workspace = page?.selectedWorkspace
        let fullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        return [
            Command(section: .palette, title: "Rename Tab", symbol: "pencil", enabled: tab != nil,
                    name: tab.map { tab in
                        (tab.label, { await page?.store.rename(tab: tab.id, label: $0) })
                    }),
            Command(section: .palette, title: "Rename Workspace", symbol: "pencil", enabled: workspace != nil,
                    name: workspace.map { workspace in
                        (workspace.label, { await page?.store.rename(workspace: workspace.id, label: $0) })
                    }),
            Command(
                section: .palette,
                title: "Font Size",
                symbol: "textformat.size",
                keywords: "text bigger smaller",
                menu: PaneTerminal.fontSizes.map { size in
                    Command(section: .palette, title: "\(size) pt", checked: settings.fontSize == size) {
                        settings.fontSize = size
                    }
                },
            ),
            // AppKit's View menu has the item and its key.
            Command(section: .palette, title: fullScreen ? "Exit Full Screen" : "Enter Full Screen",
                    key: .init("f", modifiers: [.command, .control]),
                    symbol: "arrow.up.left.and.arrow.down.right") { NSApp.keyWindow?.toggleFullScreen(nil) },
        ]
    }

    /// The Window menu's tab, workspace and page steps, and the places on ⌘1…⌘9.
    private func window(_ page: Page?, _ pages: WindowPages?) -> [Command] {
        let tabs = page?.selectedWorkspace?.tabs ?? []
        let tab = page?.selectedTab
        func step(_ title: String, _ symbol: String, _ offset: Int) -> Command {
            Command(
                section: .pages,
                title: title,
                key: .init(offset < 0 ? "[" : "]", modifiers: [.command, .option]),
                symbol: symbol,
                enabled: pages?.neighbor(offset) != nil,
                action: { pages?.step(offset) },
            )
        }
        func stepWorkspace(_ title: String, _ symbol: String, _ offset: Int) -> Command {
            Command(section: .workspaceSteps, title: title,
                    key: .init(offset < 0 ? "[" : "]", modifiers: [.command, .control]), symbol: symbol,
                    enabled: (page?.sidebarWorkspaces.count ?? 0) > 1) { page?.stepWorkspace(offset) }
        }
        return [
            Command(section: .tabSteps, title: "Show Previous Tab", key: .previousTab, symbol: "chevron.backward",
                    enabled: tabs.count > 1) { page?.step(-1) },
            Command(section: .tabSteps, title: "Show Next Tab", key: .nextTab, symbol: "chevron.forward",
                    enabled: tabs.count > 1) { page?.step(1) },
            Self.moveTab(page, -1, enabled: tab != nil && tabs.first?.id != tab?.id),
            Self.moveTab(page, 1, enabled: tab != nil && tabs.last?.id != tab?.id),
            stepWorkspace("Show Previous Workspace", "chevron.up", -1),
            stepWorkspace("Show Next Workspace", "chevron.down", 1),
            step("Previous Session", "chevron.left.2", -1),
            step("Next Session", "chevron.right.2", 1),
        ] + Self.jumps(page, pages)
    }
}

extension CommandList {
    /// ⇧⌘← ⇧⌘→, as iTerm2 (most Mac keyboards have no Page Up or Down).
    private static func moveTab(_ page: Page?, _ offset: Int, enabled: Bool) -> Command {
        let side = offset < 0 ? "left" : "right"
        return Command(section: .tabSteps, title: "Move Tab \(side.capitalized)",
                       key: .init(offset < 0 ? .leftArrow : .rightArrow, modifiers: [.command, .shift]),
                       symbol: "arrow.\(side).to.line", enabled: enabled, action: {
                           // The menu takes the arrow before a text field: there it still selects to the line's
                           // end. Not from the palette or a click (the palette's field has the keyboard then).
                           let event = NSApp.currentEvent
                           let arrow = event?.type == .keyDown && [123, 124].contains(event?.keyCode)
                           let select = offset < 0 ? #selector(NSResponder.moveToBeginningOfLineAndModifySelection)
                               : #selector(NSResponder.moveToEndOfLineAndModifySelection)
                           if arrow, let text = NSApp.keyWindow?.firstResponder as? NSTextView {
                               text.doCommand(by: select)
                           } else if let page, let tab = page.selectedTab {
                               Task { await page.store.move(tab: tab.id, by: offset) }
                           }
                       })
    }

    /// Keys that move the keyboard, the pane or a divider; and Focus Follows Mouse.
    private var paneKeys: [Command] {
        let enabled = pages?.current?.keyboardPane != nil, tab = pages?.current?.selectedTab
        let arrows: [(Heading, KeyEquivalent)] = [
            (.left, .leftArrow), (.right, .rightArrow), (.up, .upArrow), (.down, .downArrow),
        ]
        func each(_ title: String, _ modifiers: EventModifiers?, symbol suffix: String,
                  _ act: @escaping (Page, HostStore.Pane, Heading) async -> Void) -> [Command]
        {
            arrows.map { heading, key in
                Command(section: .paneKeys, title: "\(title) \(heading.rawValue.capitalized)",
                        key: modifiers.map { .init(key, modifiers: $0) },
                        family: (title, "←→↑↓"),
                        symbol: "arrow.\(heading.rawValue)\(suffix)",
                        keywords: "pane",
                        enabled: enabled, action: {
                            // A held key's repeat while a write runs is dropped, not queued behind it each time.
                            // `isARepeat` raises on a click (the palette, the menu bar).
                            let event = NSApp.currentEvent
                            if let page = pages?.current, let pane = page.keyboardPane,
                               !page.store.writing || event?.type != .keyDown || event?.isARepeat != true
                            {
                                Task { await act(page, pane, heading) }
                            }
                        })
            }
        }
        // Even when it looks even: the menu may be older than the tab's last change.
        let balance = Command(section: .paneKeys, title: "Balance Splits",
                              key: .init("=", modifiers: [.command, .option]), symbol: "equal.square",
                              keywords: "pane even", enabled: tab != nil, action: {
                                  if let page = pages?.current, let tab = page.selectedTab {
                                      Task { await page.store.balance(tab) }
                                  }
                              })
        return [balance] +
            each("Select Pane", [.command, .option], symbol: "") { page, _, heading in
                page.moveKeyboard(heading)
            }
            + [
                Command(section: .paneKeys, title: "Select Previous Pane", key: .init("["), symbol: "chevron.left",
                        keywords: "pane", enabled: enabled) { pages?.current?.stepCard(-1) },
                Command(section: .paneKeys, title: "Select Next Pane", key: .init("]"), symbol: "chevron.right",
                        keywords: "pane", enabled: enabled) { pages?.current?.stepCard(1) },
            ]
            + each("Move Pane", [.command, .option, .shift], symbol: ".square") {
                await $0.store.swap($1.id, $2)
            }
            // No key: dividers and Balance Splits cover it.
            + each("Resize Pane", nil, symbol: ".to.line") {
                await $0.store.resize($1.id, $2)
            }
            + [Command(section: .paneSetting, title: "Focus Follows Mouse", symbol: "cursorarrow.motionlines",
                       keywords: "hover pane", checked: settings.followMouse, setting: true,
                       action: { settings.followMouse.toggle() })]
    }

    /// The places on 1…9, one modifier per level: ⌘ the workspace's tabs, ⌃⌘ the sidebar's
    /// workspaces, ⌥⌘ the window's sessions. Each finds its place when the key is pressed: the menu may be older
    /// than a switch.
    static func jumps(_ page: Page?, _ pages: WindowPages?) -> [Command] {
        func jump(_ section: Command.Section, _ level: String, _ modifiers: EventModifiers, _ titles: [String],
                  _ show: @escaping (Int) -> Void) -> [Command]
        {
            func key(_ index: Int) -> KeyboardShortcut {
                KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: modifiers)
            }
            return titles.enumerated().map { index, title in
                Command(section: section, title: title, key: key(index),
                        family: ("Show \(level) 1–9", "1–9")) { show(index) }
            }
        }
        // The first 9 only: the menu bar is made again when what they read changes.
        let tabs = (page?.selectedWorkspace?.tabs ?? []).prefix(9), workspaces = page?.sidebarWorkspaces ?? []
        return jump(.tabs, "Tab", .command, tabs.map { page?.titleText($0) ?? $0.label }) { index in
            if let page, let workspace = page.selectedWorkspace, workspace.tabs.indices.contains(index) {
                page.select(workspace, tab: workspace.tabs[index].id)
            }
        } + jump(.workspaces, "Workspace", [.command, .control], workspaces.prefix(9).map(\.label)) {
            if let page, page.sidebarWorkspaces.indices.contains($0) {
                page.select(page.sidebarWorkspaces[$0])
            }
        } + jump(.sessions, "Session", [.command, .option], (pages?.list ?? []).prefix(9).map(\.id)) {
            if let pages, pages.list.indices.contains($0) {
                pages.show(pages.list[$0])
            }
        }
    }
}
