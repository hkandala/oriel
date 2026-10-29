import HerdrKit
import SwiftUI

extension CommandList {
    /// The pane's actions (D48), for View ▸ Pane on the keyboard card and the card header's context menu. Actions
    /// ask `target` for the pane when they run: the menu bar may be older than the last keyboard move. `tabs`: Move
    /// Pane to Tab lists the session's tabs (not in the menu bar).
    static func pane(_ page: Page?, tabs: Bool = true, _ target: @escaping @MainActor () -> HostStore.Pane?)
        -> [Command]
    {
        let pane = target(), zoomed = pane.map { page?.zoomedPaneID == $0.id } ?? false
        func act(_ title: String, _ key: KeyboardShortcut? = nil, _ section: Command.Section = .pane,
                 symbol: String? = nil, enabled: Bool = true, id: String? = nil, heading: String? = nil,
                 _ run: @escaping (Page, HostStore.Pane) async -> Void) -> Command
        {
            Command(section: section, title: title, id: id, key: key, group: .panes, symbol: symbol,
                    heading: heading, keywords: "pane", enabled: pane != nil && enabled, action: {
                        if let page, let pane = target() {
                            Task { await run(page, pane) }
                        }
                    })
        }
        // Every tab of the session, under its workspace's name, but the pane's own: herdr refuses
        // that move. A move into a tab lands right of its last card, as a drop on its capsule does: without a
        // target herdr splits the tab's focused pane.
        let others = (tabs ? page?.sidebarWorkspaces ?? [] : []).flatMap { workspace in
            workspace.tabs.filter { $0.id != pane?.tabID }.map { other in
                act(page?.titleText(other) ?? other.label, nil, .paneMove, id: other.id, heading: workspace.label) {
                    await $0.drop($1.id, on: .tab(other.id))
                }
            }
        }
        return [
            act("Float Pane", symbol: "pip.enter") { $0.float($1) },
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
                    enabled: pane != nil, menu: [
                        act("New Tab", nil, .paneMove, symbol: "plus.square") { page, pane in
                            if let workspace = page.store.workspace(of: pane.tabID) {
                                await page.move(pane, to: .newTab(workspaceID: workspace.id))
                            }
                        },
                        act("New Workspace", nil, .paneMove, symbol: "folder.badge.plus") {
                            await $0.move($1, to: .newWorkspace())
                        },
                    ] + others),
            Command(section: .paneMove, title: "Rename Pane…", symbol: "pencil", keywords: "pane",
                    enabled: pane != nil, name: pane.map { pane in
                        (pane.label ?? "", { await page?.store.rename(pane: pane.id, label: $0) })
                    }) { page?.renamingPaneID = target()?.id },
            // herdr's label goes: the header shows the program again. Not a plugin pane's: its label is its kind.
            act("Reset Pane Name", nil, .paneMove, symbol: "arrow.uturn.backward",
                enabled: pane?.label != nil && pane?.plugin == nil) { await $0.store.rename(pane: $1.id, label: "") },
        ] + ends(page, pane, target)
    }

    /// Replace Pane, the commands that change the pane's kind (ui/new-pane) and Close Pane: last in the pane's menus,
    /// in the File menu in the menu bar.
    private static func ends(_ page: Page?, _ pane: HostStore.Pane?,
                             _ target: @escaping @MainActor () -> HostStore.Pane?) -> [Command]
    {
        // A fresh shell in the pane's place: after a change to the shell's setup.
        let replace = Command(section: .close, title: "Replace Pane", key: .replacePane, group: .panes,
                              symbol: "arrow.clockwise.square", keywords: "pane restart new shell respawn reset",
                              enabled: pane != nil) { page?.replacePane(target()) }
        // Only on an agent or plugin pane: on a terminal it is Replace Pane.
        let terminal = pane?.agent == nil && pane?.plugin == nil ? [] : [
            Command(section: .close, title: "Open Terminal Here", group: .panes, symbol: "terminal",
                    keywords: "pane shell kind") { page?.replacePane(target(), Replacement(button: "Open Terminal")) },
        ]
        // Each on every pane but one of its kind.
        let plugins = [
            (PluginKind.browser, "web page url localhost"), (.files, "file tree explorer folder"),
            (.diff, "diff git uncommitted"),
        ].filter { pane?.plugin?.kind != $0.0 }.map { kind, keywords in
            Command(section: .close, title: "Open \(Chooser.Row.plugin(kind).labels.name) Here", group: .panes,
                    symbol: kind.symbol, keywords: "pane kind " + keywords, enabled: pane != nil, action: {
                        if let page, let pane = target() {
                            page.open(kind, in: pane)
                        }
                    })
        }
        let agent = Command(section: .close, title: "Start Agent Here", group: .panes, symbol: "sparkles",
                            keywords: "pane kind claude code codex pi opencode", enabled: pane != nil,
                            menu: Chooser.agents.map { agent in
                                Command(section: .close, title: agent.name, program: agent.command) {
                                    if let page, let pane = target() {
                                        page.start(agent, in: pane)
                                    }
                                }
                            })
        return [replace] + terminal + [agent] + plugins + [
            Command(section: .close, title: "Close Pane", key: .closePane, group: .panes, symbol: "xmark.square",
                    keywords: "pane", enabled: pane != nil || page?.standIn != nil) { page?.closePane(target()) },
        ]
    }
}

extension CommandList {
    /// The floating window's commands (D50): only what applies to it.
    func floatingCommands(_ floating: Floating) -> [Command] {
        let terminalID = floating.terminalID
        guard let page = pages?.withFloats.first(where: { $0.id == floating.session }) else { return [] }
        let pane = page.store.panes.first { $0.terminalID == terminalID }
        let terminal = pane.flatMap(page.terminal)
        var main = self
        main.floating = nil
        let sizes = main.all.filter { $0.section == .size || $0.title == "Font Size" }
        func edit(_ title: String, _ action: Selector, _ symbol: String) -> Command {
            Command(section: .palette, title: title, symbol: symbol, enabled: terminal != nil) {
                if let terminal {
                    NSApp.sendAction(action, to: terminal.view, from: nil)
                }
            }
        }
        return [
            Command(section: .close, title: "Detach Pane", key: .closePane, symbol: "pip.exit") {
                page.floating[terminalID] = nil
            },
            Command(section: .view, title: "Command Palette", key: .palette, symbol: "command",
                    enabled: palette != nil) { palette?.wrappedValue.toggle() },
            Command(section: .view, title: "Stay on Top", symbol: "pin", checked: page.floating[terminalID] == true,
                    setting: true) { page.floating[terminalID]?.toggle() },
            Command(section: .edit, title: "Find…", key: .init("f"), symbol: "magnifyingglass",
                    enabled: pane.map { $0.plugin == nil } == true) { page.openFind(pane) },
            Command(section: .edit, title: "Find Next", key: .findNext, symbol: "chevron.down",
                    enabled: page.find != nil) { Task { await page.find?.step(1) } },
            Command(section: .edit, title: "Find Previous", symbol: "chevron.up", enabled: page.find != nil) {
                Task { await page.find?.step(-1) }
            },
            edit("Copy", #selector(NSText.copy(_:)), "doc.on.doc"),
            edit("Paste", #selector(NSText.paste(_:)), "doc.on.clipboard"),
        ] + Self.pane(page, tabs: false) { pane }.filter { $0.section == .close }.map {
            // ⌘W detaches, as the red light.
            var command = $0
            command.key = command.key == .closePane ? .closeTab : command.key
            return command
        } + sizes + Self.browser(pane.flatMap(page.browser))
    }
}
