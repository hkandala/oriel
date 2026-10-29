import AppKit
import SwiftUI

extension CommandList {
    /// A plugin card's commands, in the main and the floating windows: Save for a file's text, Edit Mode for a
    /// markdown card's. Their keys only there: a disabled item would keep ⌘S or ⌘E from a terminal.
    static func plugin(_ plugin: Plugin?) -> [Command] {
        let file = [.file, .markdown].contains(plugin?.kind) ? plugin?.file : nil, markdown = plugin?.kind == .markdown
        let edits = markdown && file?.loaded == true && file?.readOnly == false
        return [
            Command(section: .view, title: "Edit Mode", key: edits ? .init("e") : nil, symbol: "pencil",
                    keywords: "markdown read", enabled: edits, checked: markdown ? plugin?.editing == true : nil,
                    action: { plugin?.editing.toggle() }),
            Command(
                section: .close,
                title: "Save",
                key: file == nil ? nil : .init("s"),
                symbol: "square.and.arrow.down",
                keywords: "file write",
                enabled: file?.loaded == true && file?.readOnly == false && file?.failure == nil,
                action: {
                    Task { await file?.save() }
                },
            ),
        ]
    }

    /// Find, Find Next and Find Previous: a file card's text view with the keyboard shows the system find bar and
    /// steps through it (Markdown's Read goes to Edit for it); a terminal (`terminal`) the app's find bar. As in Rex, a
    /// terminal's Find Previous has no key: ⇧⌘G is Go to Directory.
    static func find(_ page: Page?, _ pane: HostStore.Pane?, terminal: Bool) -> [Command] {
        let text = page?.hasText(pane) == true, find = page?.find
        let plugin = pane.flatMap { page?.plugin($0) }
        func command(_ title: String, _ key: KeyboardShortcut?, _ symbol: String, _ action: NSTextFinder.Action,
                     else other: @escaping () -> Void) -> Command
        {
            let enabled = action == .showFindInterface ? terminal : find != nil
            return Command(section: .edit, title: title, key: key, symbol: symbol, keywords: "search scrollback",
                           enabled: text || enabled, action: {
                               guard text else { return other() }
                               if let plugin, plugin.kind == .markdown, !MarkdownCard.showsText(plugin) {
                                   plugin.find = action
                                   plugin.editing = true
                               } else {
                                   findInText(action)
                               }
                           })
        }
        return [
            command("Find…", .init("f"), "magnifyingglass", .showFindInterface) {
                page?.openFind(pane)
            },
            command("Find Next", .findNext, "chevron.down", .nextMatch) {
                Task { await page?.find?.step(1) }
            },
            command("Find Previous", text ? .findPrevious : nil, "chevron.up", .previousMatch) {
                Task { await page?.find?.step(-1) }
            },
        ]
    }
}

extension CommandList {
    /// The text view with the keyboard shows the system find bar or steps through it.
    static func findInText(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: sender)
    }
}

extension Page {
    /// The pane's card shows a file's text: Find acts on it.
    func hasText(_ pane: HostStore.Pane?) -> Bool {
        guard let plugin = pane.flatMap(plugin) else { return false }
        return [.file, .markdown].contains(plugin.kind) && plugin.file.loaded
    }
}
