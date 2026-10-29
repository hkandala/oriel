import AppKit
import SwiftUI

extension CommandList {
    /// A plugin card's commands, in the main and the floating windows: Save for a file's text. Its key only there: a
    /// disabled item would keep ⌘S from a terminal.
    static func plugin(_ plugin: Plugin?) -> [Command] {
        let file = plugin?.file
        return [
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
    /// steps through it; a terminal (`terminal`) the app's find bar. As in Rex, a terminal's Find Previous has no key:
    /// ⇧⌘G is Go to Directory.
    static func find(_ page: Page?, _ pane: HostStore.Pane?, terminal: Bool) -> [Command] {
        let text = page?.hasText(pane) == true, find = page?.find
        func command(_ title: String, _ key: KeyboardShortcut?, _ symbol: String, _ action: NSTextFinder.Action,
                     else other: @escaping () -> Void) -> Command
        {
            let enabled = action == .showFindInterface ? terminal : find != nil
            return Command(section: .edit, title: title, key: key, symbol: symbol, keywords: "search scrollback",
                           enabled: text || enabled, action: {
                               guard text else { return other() }
                               let sender = NSMenuItem()
                               sender.tag = action.rawValue
                               NSApp.sendAction(
                                   #selector(NSTextView.performTextFinderAction(_:)),
                                   to: nil,
                                   from: sender,
                               )
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

extension Page {
    /// The pane's card shows a file's text: Save and Find act on it.
    func hasText(_ pane: HostStore.Pane?) -> Bool {
        pane.flatMap(plugin)?.file?.loaded == true
    }
}
