import HerdrKit
import SwiftUI

/// Replace Pane (⌘R): a fresh shell in the pane's place, size and folder, as after a change to the shell's setup.
extension HostStore {
    /// herdr 0.9.5 has no respawn: the pane is split (herdr starts the new one in the pane's live folder) and closed,
    /// so the new one fills the old one's place in the tree, at its size. The new pane hides until the old one is
    /// gone (`Ahead.replacing`). `made` runs as herdr makes the new pane, before the close.
    func replace(_ paneID: String, made: (HerdrKit.Pane) -> Void) async {
        guard let tabID = pane(paneID)?.tabID else { return }
        let known = (last?.panes ?? []).filter { $0.tabID == tabID }.map(\.id)
        ahead.replacing[paneID] = (tabID, Set(known))
        let done = await write { client in
            guard let new = try await client.split(paneID, .right) else {
                throw HerdrError.failed("herdr named no pane")
            }
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

extension Page {
    /// Replace Pane: asks first in this window when something besides the shell runs, as Close Pane does (D41). Not
    /// the old keyboard card while a split's lit stand-in waits for herdr's pane (as `closePane`).
    func replacePane(_ pane: HostStore.Pane?) {
        let key = "replace \(pane?.id ?? "")"
        guard let pane, let client = store.client, store.ahead.replacing[pane.id] == nil, !asking.contains(key),
              newest.map({ store.pane($0.id) != nil || pane.id != keyboardPane?.id }) ?? true else { return }
        asking.insert(key)
        Task {
            let running = await store.programs([pane.id], starting: pane.starting ? [pane.id] : [], client)
            asking.remove(key)
            if running.isEmpty {
                await replace(pane.id)
            } else {
                closing = HostStore.Closing(close: .pane(pane.id), running: running.sorted(), replace: true)
            }
        }
    }

    /// A replaced pane's zoom goes to its new pane, after each snapshot.
    func zoomReplaced() {
        if let new = zoomedPaneID.flatMap({ store.ahead.replaced[$0] }) {
            zoomedPaneID = new
        }
    }

    /// Without asking. The new pane gets the keyboard, the old one's zoom (`settle`) or its floating window, where
    /// that window is.
    func replace(_ paneID: String) async {
        let old = store.pane(paneID)?.terminalID, pinned = old.flatMap { floating[$0] }
        await store.replace(paneID) { new in
            guard let terminalID = new.terminalID else { return }
            if let old, let pinned {
                floating[terminalID] = pinned
                NSApp.windows.first { $0.frameAutosaveName == "float \(old)" }?
                    .saveFrame(usingName: "float \(terminalID)")
                WindowPages.openWindow?(id: "float", value: Floating(session: id, terminalID: terminalID))
            } else {
                follow(new, terminalID, select: false)
            }
        }
    }
}
