import HerdrKit
import SwiftUI

/// The ways a browser or plugin pane opens: the chooser's rows, Open ‹Kind› Here and linked opens.
extension Page {
    /// A browser or plugin pane takes the chooser's pane's place, with Replace Pane's steps (ui/new-pane#browser). It
    /// waits for a snapshot that has the pane: herdr's split or tab answer comes before one, and a fast pick (⌘D,
    /// then 3) would find nothing to replace.
    func open(_ kind: PluginKind, _ chooser: Chooser) {
        guard chooser.starting == nil, chooser.opening == nil else { return }
        chooser.opening = kind
        Task {
            defer { store.drop(chooser) }
            let clock = ContinuousClock(), begun = clock.now
            while chooser.paneID.flatMap(store.pane).flatMap({ store.workspace(of: $0.tabID) }) == nil,
                  clock.now - begun < .seconds(10), store.choosers.contains(where: { $0 === chooser })
            {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let id = chooser.paneID {
                await replace(id, Replacement(plugin: kind))
            }
        }
    }

    /// Open Browser, File Explorer or Git Here: the chooser's pick on a pane that shows it, else a Replace Pane.
    func open(_ kind: PluginKind, in pane: HostStore.Pane) {
        if let chooser = store.chooser(pane.id) {
            open(kind, chooser)
        } else {
            replacePane(pane, Replacement(button: "Open \(Chooser.Row.plugin(kind).labels.name)", plugin: kind))
        }
    }

    /// A linked open from the card of terminal `source`: a new herdr tab right after the card's tab, in its workspace
    /// and folder (also from a floating window), which the snapshot after it selects with the keyboard; after the
    /// selected tab once the card is gone. Its card lands at a line of a file or a diff's file, once (not in the
    /// label).
    func open(_ kind: PluginKind, arg: String, at place: String? = nil, from source: String) async {
        let card = store.panes.first { $0.terminalID == source }
        guard let tabID = card?.tabID ?? selectedTab?.id, let workspace = store.workspace(of: tabID),
              let index = workspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let label = store.newLabel(kind, arg: arg), cwd = card?.cwd ?? keyboardPane?.cwd ?? "~"
        // A path with a control character or over 1024 characters makes no plugin label.
        guard PaneLabel(label.text) != nil else { return }
        await store.write { client in
            guard let id = try await client.newTab(workspace: workspace.id, cwd: cwd, label: label.text,
                                                   command: label.placeholder)
            else { throw HerdrError.failed("herdr named no pane") }
            let pane = try await client.pane(id)
            // ponytail: a card made from a snapshot before this line misses its landing; hand it over in the label
            // if that shows.
            if let place, let terminalID = pane.terminalID {
                terminals.landings[terminalID] = place
            }
            // herdr adds it last: before the tab now after the card's.
            try await client.move(tab: pane.tabID, to: index + 1)
            follow(pane, pane.terminalID)
        }
    }
}

extension HostStore {
    /// The label's argument of a pane opened in this folder: for File Explorer and Git, the folder's git repository's
    /// root, else the folder; the File Explorer's with the `/` of a folder.
    func arg(_ kind: PluginKind, in folder: String) async -> String {
        guard kind != .browser else { return "" }
        var root = folder
        if await gitRuns(), let repo = await Git.root(folder, exec: machine.exec()) {
            root = repo
        }
        return kind == .git || root.hasSuffix("/") ? root : root + "/"
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
