import HerdrKit
import SwiftUI

extension Ahead {
    /// A Replace Pane under way (`replacing`), or done in the last snapshot (`replaced`).
    struct Replacing {
        let tabID: String
        /// The session's panes when it was asked.
        let known: Set<String>
        /// The old pane's terminal.
        let terminal: String?
        /// herdr's answer to the split: the new pane.
        var made: HerdrKit.Pane?
        /// A plugin pane's label: hidden in the tab it is made in too, which then drops out (it showed for a
        /// snapshot, and its going took the pane out of the keyboard history).
        var label: String?

        /// The new panes, hidden until the old one is gone.
        func hidden(_ panes: [HerdrKit.Pane]) -> [String] {
            panes.filter { $0.tabID == tabID && !known.contains($0.id) || label != nil && $0.label == label }.map(\.id)
        }
    }

    /// `cards` after a show: the new panes still there, and the ones that just took replaced panes' places.
    mutating func keepCards(_ ids: [String]) {
        cards = cards.filter { ids.contains($0.key) }.merging(replaced.compactMap { old, new in
            new.made.map { ($0.id, old) }
        }) { $1 }
    }
}

/// Replace Pane (⇧⌘R): a fresh shell in the pane's place, size and folder, as after a change to the shell's setup.
extension HostStore {
    /// herdr 0.9.5 has no respawn: the pane is split (herdr starts the new one in the pane's live folder) and closed,
    /// so the new one fills the old one's place in the tree, at its size. The new pane hides until the old one is
    /// gone (`Ahead.replacing`). `made` runs as herdr makes the new pane, before the close.
    /// A browser or plugin pane (`kind`) is made with its label and placeholder in a new tab, then moved beside the
    /// pane (future-work/plugins/labels#create).
    func replace(_ paneID: String, kind: PluginKind? = nil, made: (HerdrKit.Pane) -> Void) async {
        guard let old = pane(paneID), let workspace = workspace(of: old.tabID) else { return }
        ahead.replacing[paneID] = Ahead.Replacing(tabID: old.tabID, known: Set(last?.panes.map(\.id) ?? []),
                                                  terminal: old.terminalID)
        let done = await write { client in
            var new: HerdrKit.Pane?
            if let kind {
                // In the pane's live folder, as a split is.
                let cwd = try await client.pane(paneID).cwd ?? old.cwd ?? "~"
                let label = await newLabel(kind, arg: arg(kind, in: cwd))
                ahead.replacing[paneID]?.label = label.text
                if let tab = try await client.newTab(workspace: workspace.id, cwd: cwd, label: label.text,
                                                     command: label.placeholder)
                {
                    do {
                        new = try await client.move(pane: tab, to: .tab(old.tabID, beside: paneID))
                    } catch {
                        // Not left behind in its own tab.
                        try? await client.close(pane: tab)
                        throw error
                    }
                }
            } else {
                new = try await client.split(paneID, .right)
            }
            guard let new else {
                throw HerdrError.failed("herdr named no pane")
            }
            ahead.replacing[paneID]?.made = new
            made(new)
            try await client.close(pane: paneID)
        }
        // The old pane stays, and the new one, if made, shows beside it.
        if !done {
            ahead.replacing[paneID] = nil
            redraw()
        }
    }
}

/// What Replace Pane's new pane shows, and the red button of its question (ui/new-pane): Replace Pane gives an agent
/// pane's new pane the chooser; Open Terminal Here and Start Agent Here are replaces too.
struct Replacement {
    var button = "Replace Pane"
    /// The chooser, or the loader while this agent starts.
    var chooser = false
    var agent: Chooser.Agent?
    /// A browser or plugin pane (Open Browser Here, the chooser's Browser).
    var plugin: PluginKind?
}

extension Page {
    /// Replace Pane: asks first in this window when something besides the shell runs, as Close Pane does (D41). Not
    /// the old keyboard card while a split's lit stand-in waits for herdr's pane (as `closePane`), nor a held ⇧⌘R's
    /// repeats.
    func replacePane(_ pane: HostStore.Pane?, _ replacement: Replacement? = nil) {
        let key = "replace \(pane?.id ?? "")", event = NSApp.currentEvent
        guard let pane, let client = store.client, store.ahead.replacing[pane.id] == nil, !asking.contains(key),
              event?.type != .keyDown || event?.isARepeat != true,
              newest.map({ store.pane($0.id) != nil || pane.id != keyboardPane?.id }) ?? true else { return }
        let replacement = replacement ?? Replacement(chooser: pane.agent != nil || pane.plugin != nil)
        asking.insert(key)
        Task {
            let running = await store.programs([pane.id], starting: pane.starting ? [pane.id] : [],
                                               placeholders: pane.plugin != nil ? [pane.id] : [], client)
            asking.remove(key)
            if running.isEmpty {
                await replace(pane.id, replacement)
            } else {
                closing = HostStore.Closing(close: .pane(pane.id), running: running.sorted(), replace: replacement)
            }
        }
    }

    /// Without asking. The new pane gets the keyboard at herdr's answer, as a moved pane does; a floated one's
    /// window as the old one's closes (`floatReplaced`).
    func replace(_ paneID: String, _ replacement: Replacement) async {
        let old = store.pane(paneID)?.terminalID
        await store.replace(paneID, kind: replacement.plugin) { new in
            if replacement.chooser {
                store.choose(new, starting: replacement.agent)
            }
            if old.flatMap({ floating[$0] }) == nil {
                follow(new, new.terminalID, select: false)
            }
        }
    }

    /// A replaced pane's zoom goes to its new pane, after each snapshot.
    func zoomReplaced() {
        if let new = zoomedPaneID.flatMap({ store.ahead.replaced[$0]?.made?.id }) {
            zoomedPaneID = new
        }
    }

    /// A replaced floated pane's new pane floats in a window where the old one is, with its Stay on Top, in the
    /// snapshot that shows it, before the old one's window closes (`HostStore.snapshotted`): it opens with its
    /// terminal drawn, and a float-only page keeps a float.
    func floatReplaced() {
        for replaced in store.ahead.replaced.values {
            guard let old = replaced.terminal, let pinned = floating[old], let new = replaced.made?.terminalID
            else { continue }
            floating[new] = pinned
            // Out of the way first: a new window over one of its group at the same place is cascaded 29 pt off.
            let window = FloatFrames.windows.object(forKey: old as NSString)
            window?.orderOut(nil)
            FloatFrames.open(
                Floating(session: id, terminalID: new),
                over: terminals.pages?.window,
                frame: window?.frame,
                with: WindowPages.openWindow,
            )
        }
    }
}
