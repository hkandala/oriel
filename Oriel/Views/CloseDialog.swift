import HerdrKit
import SwiftUI

/// A close or a Replace Pane waiting for the user's yes (D41), in the window it was asked in: a floated pane's in
/// its floating window (D50), every other in the main window.
struct CloseDialog: ViewModifier {
    let page: Page
    /// The floating window's pane.
    var floated: String?

    func body(content: Content) -> some View {
        let closing = page.closing.flatMap { closing in
            guard case let .pane(id) = closing.close, page.store.pane(id).map(page.floats) == true else {
                return floated == nil ? closing : nil
            }
            return floated == id ? closing : nil
        }
        let dialog = dialog(closing)
        // An alert: a confirmation dialog ignored its .defaultAction button's Return.
        content.alert(dialog?.title ?? "", isPresented: Binding { closing != nil } set: {
            if !$0 {
                page.closing = nil
            }
        }, presenting: closing) { closing in
            Button(closing.replace ? "Replace Pane" : closing.close.button, role: .destructive) {
                Task {
                    if closing.replace, let id = closing.close.paneID {
                        await page.replace(id)
                    } else {
                        await page.store.close(closing.close)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(dialog?.message ?? "")
        }
    }

    /// The close dialog's text (design D41): what runs, and that a close ends it on every device for good.
    private func dialog(_ closing: HostStore.Closing?) -> (title: String, message: String)? {
        guard let closing else { return nil }
        let store = page.store
        let tabs = store.tabIDs(closing.close)
        let running = closing.running.formatted(.list(type: .and))
            + (closing.running.count == 1 ? " is" : " are") + " running in "
        let end = " will end, here and in every herdr client. This cannot be undone."
        let count = store.panes.count { tabs.contains($0.tabID) }
        let them = count == 1 ? "pane and everything running in it"
            : "\(count) panes and everything running in them"
        switch closing.close {
        case let .tab(id):
            let tab = store.workspaces.flatMap(\.tabs).first { $0.id == id }
            return ("Close the tab “\(tab.map(page.titleText) ?? id)”?", running + "it. Its " + them + end)
        case let .otherTabs(others, right):
            let which = others.count == 1 ? right ? "the tab to the right" : "the other tab"
                : right ? "the \(others.count) tabs to the right" : "the \(others.count) other tabs"
            return ("Close \(which)?", running + "them. Their " + them + end)
        case let .pane(id):
            let name = store.pane(id).map { $0.label ?? $0.folder ?? "terminal" } ?? id
            return ("\(closing.replace ? "Replace" : "Close") “\(name)”?", running + "it and" + end)
        case let .workspace(id):
            let worktrees = store.worktrees(of: id)
            let also = worktrees.isEmpty ? "" : worktrees.count == 1 ? " and its worktree’s workspace"
                : " and its \(worktrees.count) worktrees’ workspaces"
            let label = store.workspaces.first { $0.id == id }?.label ?? id
            return ("Close the workspace “\(label)”\(also)?",
                    running + "it. \(tabs.count == 1 ? "Its tab" : "Its \(tabs.count) tabs"), " + them + end)
        }
    }
}

private extension HostStore.Close {
    var button: String {
        switch self {
        case .pane: "Close Pane"
        case .tab: "Close Tab"
        case .otherTabs: "Close Tabs"
        case .workspace: "Close Workspace"
        }
    }
}
