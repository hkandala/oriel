import HerdrKit
import SwiftUI

extension Page {
    /// The card with the keyboard when it takes ⌘S or ⌘F: the menu's Save and Find go to its page.
    var editor: Plugin? {
        editor(keyboardPane)
    }

    /// Find Next (1) or Previous (-1): in the editor's page, else in the terminal's find bar.
    func findStep(_ step: Int, in editor: Plugin?) {
        if let editor {
            editor.command(step > 0 ? "findNext" : "findPrevious")
        } else {
            Task { await find?.step(step) }
        }
    }

    /// The pane's card when it takes ⌘S or ⌘F (`handles`): File Explorer's File and Markdown.
    func editor(_ pane: HostStore.Pane?) -> Plugin? {
        pane.flatMap(plugin).flatMap { $0.handles("save") || $0.handles("find") ? $0 : nil }
    }
}

extension CommandList {
    /// Save, Find…, Find Next and Find Previous, in the main and the floating windows. Over a card that
    /// takes them (`editor`, asked again when an item runs: the menu bar may be older than the last keyboard move)
    /// they act in its page; else Find opens `pane`'s find bar (the keyboard card's when nil) when `terminal`. ⌘S and
    /// ⇧⌘G have their key only over an editor: a disabled item would swallow them elsewhere (⇧⌘G is Go to Directory).
    static func editorCommands(page: Page?, pane: HostStore.Pane?, terminal: Bool,
                               _ editor: @escaping @MainActor () -> Plugin?) -> [Command]
    {
        // A plugin's card takes only what its manifest `handles`.
        let finder = { editor().flatMap { $0.handles("find") ? $0 : nil } }
        let save = editor()?.handles("save") == true, over = finder() != nil, find = page?.find != nil
        return [
            Command(section: .file, title: "Save", key: save ? .save : nil, symbol: "square.and.arrow.down",
                    enabled: save) { editor()?.command("save") },
            Command(section: .edit, title: "Find…", key: .init("f"), symbol: "magnifyingglass",
                    keywords: "search scrollback", enabled: terminal || over, action: {
                        if let editor = finder() {
                            editor.command("find")
                        } else {
                            page?.openFind(pane)
                        }
                    }),
            Command(section: .edit, title: "Find Next", key: .findNext, symbol: "chevron.down",
                    enabled: find || over) { page?.findStep(1, in: finder()) },
            Command(section: .edit, title: "Find Previous", key: over ? .findPrevious : nil, symbol: "chevron.up",
                    enabled: find || over) { page?.findStep(-1, in: finder()) },
        ]
    }
}
