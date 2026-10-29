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

    /// Open Browser, Files or Changes Here: the chooser's pick on a pane that shows it, else a Replace Pane.
    func open(_ kind: PluginKind, in pane: HostStore.Pane) {
        if let chooser = store.chooser(pane.id) {
            open(kind, chooser)
        } else {
            replacePane(pane, Replacement(button: "Open \(Chooser.Row.plugin(kind).labels.name)", plugin: kind))
        }
    }

    /// A linked open: a new herdr tab right after the selected one, in its workspace, which the snapshot after it
    /// selects with the keyboard.
    func open(_ kind: PluginKind, arg: String) async {
        guard let workspace = selectedWorkspace,
              let index = workspace.tabs.firstIndex(where: { $0.id == selectedTab?.id }) else { return }
        let label = store.newLabel(kind, arg: arg), cwd = keyboardPane?.cwd ?? "~"
        await store.write { client in
            guard let id = try await client.newTab(workspace: workspace.id, cwd: cwd, label: label.text,
                                                   command: label.placeholder)
            else { throw HerdrError.failed("herdr named no pane") }
            let pane = try await client.pane(id)
            // herdr adds it last: before the tab now after the selected one.
            try await client.move(tab: pane.tabID, to: index + 1)
            follow(pane, pane.terminalID)
        }
    }

    /// The label's argument of a pane made in this pane's place: for Files and Changes, the git repository's root
    /// of the pane's live folder, else the folder; a diff of its uncommitted changes.
    func arg(_ kind: PluginKind, of paneID: String) async -> String {
        guard kind == .files || kind == .diff else { return "" }
        let live = try? await store.client?.pane(paneID)
        let folder = live?.cwd ?? store.pane(paneID)?.cwd ?? "~"
        var root = folder
        if await gitUsable.value, let repo = await Git.root(folder, exec: store.machine.exec()) {
            root = repo
        }
        return kind == .diff ? "\(root) uncommitted" : root
    }
}
