import HerdrKit
import SwiftUI

/// Where a plugin card opens a file or a diff (ui/plugins): in the card (a click or a double-click), in a new tab
/// beside the card's tab (⌘), or in a pane to the card's side (⌥).
enum Opening: String {
    case here, tab, side
}

/// The ways a browser or plugin pane opens: the chooser's rows, Open ‹Kind› Here and linked opens.
extension Page {
    /// A browser or plugin pane takes the chooser's pane's place, with Replace Pane's steps (ui/new-pane#browser). It
    /// waits for a snapshot that has the pane: herdr's split or tab answer comes before one, and a fast pick (⌘D,
    /// then 3) would find nothing to replace.
    func open(_ plugin: PluginManifest, _ chooser: Chooser) {
        guard chooser.starting == nil, chooser.opening == nil else { return }
        chooser.opening = plugin
        Task {
            defer {
                // Kept while the replace waits for its snapshot (`drop(closed:)` drops it then): else the old pane's
                // shell showed until the new pane took its place.
                if chooser.paneID.map({ store.ahead.replacing[$0] == nil }) ?? true {
                    store.drop(chooser)
                }
            }
            let clock = ContinuousClock(), begun = clock.now
            while chooser.paneID.flatMap(store.pane).flatMap({ store.workspace(of: $0.tabID) }) == nil,
                  clock.now - begun < .seconds(10), store.choosers.contains(where: { $0 === chooser })
            {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let id = chooser.paneID {
                await replace(id, Replacement(plugin: plugin))
            }
        }
    }

    /// Open ‹chooser› Here: the chooser's pick on a pane that shows it, else a Replace Pane.
    func open(_ plugin: PluginManifest, in pane: HostStore.Pane) {
        if let chooser = store.chooser(pane.id) {
            open(plugin, chooser)
        } else {
            replacePane(pane, Replacement(button: "Open \(plugin.chooser ?? plugin.name)", plugin: plugin))
        }
    }

    /// An open from the card of terminal `source`: in the card itself when it is of that kind (`Plugin.go`); else a
    /// linked open, a new herdr tab right after the card's tab, in its workspace and folder (also from a floating
    /// window), or a pane to the card's side, which the snapshot after it selects with the keyboard; after the
    /// selected tab once the card is gone. Its card lands at a line of a file or a diff's file, once (not in the
    /// label).
    func open(_ plugin: PluginManifest, arg: String, at place: String? = nil, from source: String,
              how: Opening) async
    {
        if how == .here, let shown = terminals.builtPlugin(source), shown.manifest.id == plugin.id {
            return shown.go(arg, at: place)
        }
        let card = store.panes.first { $0.terminalID == source }
        guard let tabID = card?.tabID ?? selectedTab?.id, let workspace = store.workspace(of: tabID),
              let index = workspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let label = store.newLabel(plugin, arg: arg), cwd = card?.cwd ?? keyboardPane?.cwd ?? "~"
        // A path with a control character or over 1024 characters makes no plugin label.
        guard PaneLabel(label.text) != nil else { return }
        await store.write { client in
            guard let id = try await client.newTab(workspace: workspace.id, cwd: cwd, label: label.text,
                                                   command: label.placeholder)
            else { throw HerdrError.failed("herdr named no pane") }
            var pane = try await client.pane(id)
            // ponytail: herdr makes no split with a command, so the new tab shows for a snapshot before its pane
            // moves beside the card; hide it as Replace Pane does if that flash shows.
            if how == .side, let card {
                do {
                    pane = try await client.move(pane: id, to: .tab(card.tabID, beside: card.id)) ?? pane
                } catch {
                    try? await client.close(pane: id)
                    throw error
                }
            }
            // ponytail: a card made from a snapshot before this line misses its landing; hand it over in the label
            // if that shows.
            if let place, let terminalID = pane.terminalID {
                terminals.landings[terminalID] = place
            }
            // herdr adds it last: before the tab now after the card's.
            if how != .side || card == nil {
                try await client.move(tab: pane.tabID, to: index + 1)
            }
            follow(pane, pane.terminalID)
        }
    }
}

extension HostStore {
    /// The label's argument of a pane opened in this folder: for a plugin that opens folders or repositories (File
    /// Explorer, Git), the folder's git repository's root, else the folder, with the `/` of a folder; else none.
    func arg(_ plugin: PluginManifest, in folder: String) async -> String {
        guard plugin.opens.folders || plugin.opens.git else { return "" }
        var root = folder
        if await gitRuns(), let repo = await Git.root(folder, exec: machine.exec()) {
            root = repo
        }
        return root.hasSuffix("/") ? root : root + "/"
    }

    /// Git runs on a remote machine as it is (one without git fails, harmlessly), on This Mac only once its check
    /// passed: `/usr/bin/git` without the developer tools opens their install dialog.
    func gitRuns() async -> Bool {
        if machine.isRemote {
            return true
        }
        return await gitUsable.value
    }
}
