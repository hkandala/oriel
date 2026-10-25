#if os(macOS)
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
        let openWindow: OpenWindowAction
        let settings: AppSettings

        var all: [Command] {
            let page = pages?.current, pages = pages, workspace = page?.selectedWorkspace, tab = page?.selectedTab
            let live = page?.store.state == .live
            let file = [
                Command(section: .file, title: "New Window", key: .init("n"), symbol: "macwindow.badge.plus") {
                    openWindow(id: "main")
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
                        enabled: page?.keyboardPane?.program?.isShell == true, action: {
                            Task { await page?.choosePath(directory: true) }
                        }),
            ]
            let close = [
                Command(section: .close, title: "Close Tab", key: .init("w", modifiers: [.command, .option]),
                        group: .tabs, symbol: "xmark.rectangle", enabled: tab != nil, action: {
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
                Command(section: .close, title: "Close Workspace", symbol: "folder.badge.minus",
                        enabled: workspace != nil, action: {
                            if let page, let workspace = page.selectedWorkspace {
                                page.close(.workspace(workspace.id))
                            }
                        }),
                Command(section: .close, title: "Close Page", symbol: "rectangle.stack.badge.minus",
                        enabled: (pages?.list.count ?? 0) > 1, action: {
                            if let pages, let page = pages.current {
                                pages.close(page)
                            }
                        }),
                Command(section: .close, title: "Close Window", key: .init("w", modifiers: [.command, .shift]),
                        symbol: "xmark") { NSApp.keyWindow?.performClose(nil) },
            ]
            let find = page?.find
            let edit = [
                Command(section: .edit, title: "Insert Path…", key: .init("i", modifiers: [.command, .control]),
                        symbol: "text.insert", keywords: "file folder path",
                        enabled: page?.keyboardPane != nil) { Task { await page?.choosePath(directory: false) } },
                // As in Rex, Find Previous has no key: ⇧⌘G is Go to Directory.
                Command(section: .edit, title: "Find…", key: .init("f"), symbol: "magnifyingglass",
                        keywords: "search scrollback", enabled: live && page?.keyboardPane != nil) { page?.openFind() },
                Command(section: .edit, title: "Find Next", key: .findNext, symbol: "chevron.down",
                        enabled: find != nil) { Task { await page?.find?.step(1) } },
                Command(section: .edit, title: "Find Previous", symbol: "chevron.up", enabled: find != nil) {
                    Task { await page?.find?.step(-1) }
                },
            ]
            return file + Self.pane(page) { [page] in page?.keyboardPane } + close + edit + view + paneKeys
                + palette(page) + window(page, pages)
        }

        private var view: [Command] {
            let size = settings.fontSize, sizes = PaneTerminal.fontSizes
            return [
                Command(section: .view, title: "Command Palette", key: .palette, symbol: "command",
                        enabled: palette != nil) { palette?.wrappedValue.toggle() },
                Command(section: .help, title: "Keyboard Shortcuts", key: .init("/"), symbol: "keyboard",
                        keywords: "keys help", enabled: shortcuts != nil) { shortcuts?.wrappedValue.toggle() },
                Command(section: .view, title: "Show Agents", key: .init("."), symbol: "list.bullet.rectangle",
                        keywords: "needs you", enabled: agents != nil && sidebar != nil,
                        checked: agents?.wrappedValue == true && sidebar?.wrappedValue == true, action: {
                            if let agents, let sidebar {
                                toggleAgents(agents, sidebar)
                            }
                        }),
                Command(section: .view, title: "Toggle Sidebar", key: .toggleSidebar, symbol: "sidebar.left",
                        enabled: sidebar != nil) { sidebar?.wrappedValue.toggle() },
                Command(section: .view, title: "Appearance", symbol: "circle.lefthalf.filled",
                        keywords: "auto light dark theme mode", menu: [Appearance.auto, .light, .dark].map { value in
                            Command(section: .view, title: value.rawValue.capitalized,
                                    checked: settings.appearance == value) { settings.appearance = value }
                        }, previews: true),
                Command(section: .view, title: "Interface Style", symbol: "paintbrush", keywords: "glass classic theme",
                        menu: [InterfaceStyle.glass, .classic].map { value in
                            Command(
                                section: .view,
                                title: value.rawValue.capitalized,
                                checked: settings.style == value,
                            ) {
                                settings.style = value
                            }
                        }, previews: true),
                // The text size (design: theme and accessibility); the key monitor takes ⌘=.
                Command(section: .size, title: "Increase Font Size", key: .bigger, symbol: "textformat.size.larger",
                        keywords: "bigger text", enabled: size < sizes.upperBound) { PaneTerminal.stepFontSize(1) },
                Command(section: .size, title: "Decrease Font Size", key: .init("-"), symbol: "textformat.size.smaller",
                        keywords: "smaller text", enabled: size > sizes.lowerBound) { PaneTerminal.stepFontSize(-1) },
                Command(section: .size, title: "Reset Font Size", key: .init("0"), symbol: "textformat.size",
                        keywords: "actual size text", enabled: size != PaneTerminal.fontSize, action: {
                            settings.fontSize = PaneTerminal.fontSize
                        }),
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
            func moveTab(_ title: String, _ key: KeyEquivalent, _ symbol: String, _ offset: Int,
                         enabled: Bool) -> Command
            {
                Command(section: .tabSteps, title: title, key: .init(key, modifiers: [.control, .shift]),
                        symbol: symbol, enabled: enabled, action: {
                            if let page, let tab = page.selectedTab {
                                Task { await page.store.move(tab: tab.id, by: offset) }
                            }
                        })
            }
            func step(_ title: String, _ symbol: String, _ offset: Int) -> Command {
                Command(
                    section: .pages,
                    title: title,
                    key: .init(offset < 0 ? "[" : "]", modifiers: [.command, .option]),
                    symbol: symbol,
                    keywords: "session",
                    enabled: pages?.neighbor(offset) != nil,
                    action: {
                        if let pages, let page = pages.neighbor(offset) {
                            pages.show(page)
                        }
                    },
                )
            }
            func stepWorkspace(_ title: String, _ symbol: String, _ offset: Int) -> Command {
                Command(section: .workspaceSteps, title: title,
                        key: .init(offset < 0 ? "[" : "]", modifiers: [.command, .control]), symbol: symbol,
                        enabled: (page?.store.workspaces.count ?? 0) > 1) { page?.stepWorkspace(offset) }
            }
            return [
                Command(section: .tabSteps, title: "Show Previous Tab", key: .previousTab, symbol: "chevron.backward",
                        enabled: tabs.count > 1) { page?.step(-1) },
                Command(section: .tabSteps, title: "Show Next Tab", key: .nextTab, symbol: "chevron.forward",
                        enabled: tabs.count > 1) { page?.step(1) },
                moveTab("Move Tab Left", .pageUp, "arrow.left.to.line", -1,
                        enabled: tab != nil && tabs.first?.id != tab?.id),
                moveTab("Move Tab Right", .pageDown, "arrow.right.to.line", 1,
                        enabled: tab != nil && tabs.last?.id != tab?.id),
                stepWorkspace("Show Previous Workspace", "chevron.up", -1),
                stepWorkspace("Show Next Workspace", "chevron.down", 1),
                step("Previous Page", "chevron.left.2", -1),
                step("Next Page", "chevron.right.2", 1),
            ] + Self.jumps(page, pages)
        }

        /// Keys that move the keyboard, the pane or a divider; and Focus Follows Mouse.
        private var paneKeys: [Command] {
            let enabled = pages?.current?.keyboardPane != nil, tab = pages?.current?.selectedTab
            let arrows: [(Heading, KeyEquivalent)] = [
                (.left, .leftArrow), (.right, .rightArrow), (.up, .upArrow), (.down, .downArrow),
            ]
            func each(_ title: String, _ modifiers: EventModifiers, symbol suffix: String,
                      _ act: @escaping (Page, HostStore.Pane, Heading) async -> Void) -> [Command]
            {
                arrows.map { heading, key in
                    Command(section: .paneKeys, title: "\(title) \(heading.rawValue.capitalized)",
                            key: .init(key, modifiers: modifiers), family: title,
                            symbol: "arrow.\(heading.rawValue)\(suffix)",
                            keywords: "pane",
                            enabled: enabled, action: {
                                // A held key's repeat while a write runs is dropped, not a "Busy" notice each time.
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
                                  key: .init("=", modifiers: [.command, .control]), symbol: "equal.square",
                                  keywords: "pane even", enabled: tab != nil, action: {
                                      if let page = pages?.current, let tab = page.selectedTab {
                                          Task { await page.store.balance(tab) }
                                      }
                                  })
            return [balance] +
                each("Select Pane", [.command, .option], symbol: "") { page, _, heading in
                    await page.moveKeyboard(heading)
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
                + each("Resize Pane", [.command, .control], symbol: ".to.line") {
                    await $0.store.resize($1.id, $2)
                }
                + [Command(section: .paneSetting, title: "Focus Follows Mouse", symbol: "cursorarrow.motionlines",
                           keywords: "hover pane", checked: settings.followMouse, setting: true,
                           action: { settings.followMouse.toggle() })]
        }
    }

    extension CommandList {
        /// The places on 1…9, one modifier per level (user, phase 25): ⌘ the workspace's tabs, ⌃⌘ the sidebar's
        /// workspaces, ⌥⌘ the window's sessions. Each finds its place when the key is pressed: the menu may be older
        /// than a switch.
        static func jumps(_ page: Page?, _ pages: WindowPages?) -> [Command] {
            func number(_ index: Int, _ modifiers: EventModifiers) -> KeyboardShortcut {
                KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: modifiers)
            }
            let tabs = (page?.selectedWorkspace?.tabs ?? []).prefix(9).enumerated().map { index, tab in
                Command(section: .tabs, title: page?.titleText(tab) ?? tab.label, key: number(index, .command),
                        family: "Show Tab 1–9", action: {
                            if let page, let workspace = page.selectedWorkspace,
                               workspace.tabs.indices.contains(index)
                            {
                                page.select(workspace, tab: workspace.tabs[index].id)
                            }
                        })
            }
            let workspaces = (page?.sidebarWorkspaces ?? []).prefix(9).enumerated().map { index, workspace in
                Command(section: .workspaces, title: workspace.label, key: number(index, [.command, .control]),
                        family: "Show Workspace 1–9", action: {
                            if let page, page.sidebarWorkspaces.indices.contains(index) {
                                page.select(page.sidebarWorkspaces[index])
                            }
                        })
            }
            let sessions = (pages?.list ?? []).prefix(9).enumerated().map { index, other in
                Command(section: .sessions, title: other.id, key: number(index, [.command, .option]),
                        family: "Show Session 1–9", action: {
                            if let pages, pages.list.indices.contains(index) {
                                pages.show(pages.list[index])
                            }
                        })
            }
            return tabs + workspaces + sessions
        }

        /// The pane's actions (D48), for View ▸ Pane on the keyboard card and the card header's context menu. Actions
        /// ask `target` for the pane when they run: the menu bar may be older than the last keyboard move.
        static func pane(_ page: Page?, _ target: @escaping @MainActor () -> HostStore.Pane?) -> [Command] {
            let pane = target(), workspace = pane.flatMap { page?.store.workspace(of: $0.tabID) }
            let zoomed = pane.map { page?.zoomedPaneID == $0.id } ?? false
            func act(_ title: String, _ key: KeyboardShortcut? = nil, _ section: Command.Section = .pane,
                     symbol: String? = nil, enabled: Bool = true,
                     _ run: @escaping (Page, HostStore.Pane) async -> Void) -> Command
            {
                Command(section: section, title: title, key: key, group: .panes, symbol: symbol, keywords: "pane",
                        enabled: pane != nil && enabled, action: {
                            if let page, let pane = target() {
                                Task { await run(page, pane) }
                            }
                        })
            }
            // herdr refuses a move into the pane's own tab. A move into a tab lands right of its last card, as a drop
            // on its capsule does: without a target herdr splits the tab's focused pane.
            let others = (workspace?.tabs ?? []).filter { $0.id != pane?.tabID }.map { other in
                var command = act(page?.titleText(other) ?? other.label) { await $0.drop($1.id, on: .tab(other.id)) }
                command.id = other.id
                return command
            }
            return [
                act("Split Right", .splitRight, symbol: "rectangle.split.2x1") { await $0.split($1.id, .right) },
                act("Split Down", .splitDown, symbol: "rectangle.split.1x2") { await $0.split($1.id, .down) },
                act("Split Left", symbol: "rectangle.lefthalf.inset.filled") {
                    await $0.split($1.id, .right, before: true)
                },
                act("Split Up", symbol: "rectangle.tophalf.inset.filled") { await $0.split($1.id, .down, before: true)
                },
                act(zoomed ? "Restore Pane" : "Zoom Pane", .zoom, symbol: "plus.magnifyingglass",
                    enabled: pane.map { page?.canZoom($0.id) == true } ?? false) { $0.zoom($1.id) },
                Command(section: .paneMove, title: "Move Pane to Tab", symbol: "arrow.right.square", keywords: "pane",
                        enabled: pane != nil, menu: others + [
                            act("New Tab", nil, .paneMove, symbol: "plus.square") { page, pane in
                                if let workspace = page.store.workspace(of: pane.tabID) {
                                    await page.move(pane, to: .newTab(workspaceID: workspace.id))
                                }
                            },
                            act("New Workspace", nil, .paneMove, symbol: "folder.badge.plus") {
                                await $0.move($1, to: .newWorkspace)
                            },
                        ]),
                Command(section: .paneMove, title: "Rename Pane…", symbol: "pencil", keywords: "pane",
                        enabled: pane != nil, name: pane.map { pane in
                            (pane.label ?? "", { await page?.store.rename(pane: pane.id, label: $0) })
                        }) {
                    if let page, let pane = target() {
                        page.renamingPaneID = pane.id
                    }
                },
                act("Close Pane", .closePane, .close, symbol: "xmark.square") { $0.close(.pane($1.id)) },
            ]
        }
    }
#endif
