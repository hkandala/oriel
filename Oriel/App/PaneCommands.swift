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
            // herdr's label goes: the header shows the program again.
            act("Reset Pane Name", nil, .paneMove, symbol: "arrow.uturn.backward",
                enabled: pane?.label != nil) { await $0.store.rename(pane: $1.id, label: "") },
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
        // Only on an agent pane: on a terminal it is Replace Pane.
        let terminal = pane?.agent == nil ? [] : [
            Command(section: .close, title: "Open Terminal Here", group: .panes, symbol: "terminal",
                    keywords: "pane shell kind") { page?.replacePane(target(), Replacement(button: "Open Terminal")) },
        ]
        let agent = Command(section: .close, title: "Start Agent Here", group: .panes, symbol: "sparkles",
                            keywords: "pane kind claude code codex pi opencode", enabled: pane != nil,
                            menu: Chooser.agents.map { agent in
                                Command(section: .close, title: agent.name) {
                                    if let page, let pane = target() {
                                        page.start(agent, in: pane)
                                    }
                                }
                            })
        return [replace] + terminal + [
            agent,
            Command(section: .close, title: "Close Pane", key: .closePane, group: .panes, symbol: "xmark.square",
                    keywords: "pane", enabled: pane != nil || page?.standIn != nil) { page?.closePane(target()) },
        ]
    }
}
