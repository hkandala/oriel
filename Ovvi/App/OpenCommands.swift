import HerdrKit
import SwiftUI

extension CommandList {
    /// ⌘K's Open File…, Open Working Tree and Open Commit… (ui/window#command-palette): the card `ovvi open` makes,
    /// from the keyboard card's folder.
    static func opens(_ page: Page?) -> [Command] {
        let folder = page?.keyboardPane?.cwd != nil
        return [
            Command(section: .palette, title: "Open File…", group: .panes, symbol: "doc",
                    keywords: "path paste preview image video markdown", enabled: page?.selectedTab != nil,
                    field: ("Path", { page?.open(path: $0) })),
            Command(section: .palette, title: "Open Working Tree", group: .panes, symbol: "plusminus",
                    keywords: "git diff uncommitted changes status", enabled: folder) { page?.openGit("uncommitted") },
            Command(section: .palette, title: "Open Commit…", group: .panes, symbol: "smallcircle.filled.circle",
                    keywords: "git sha hash ref show", enabled: folder,
                    field: ("Hash or ref", { page?.openGit($0) })),
        ]
    }
}

extension Page {
    /// A path typed or pasted in the palette, with its default plugin: in a new tab, or to the side with ⌥ (⌥Return,
    /// ⌥-click). Read as the key or click comes in.
    func open(path text: String) {
        let how = Self.how
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            guard let path = await resolve(text) else {
                return await store.show(Notice(text: "No file or folder \(text)", tone: .warning))
            }
            await open(path, [], how)
        }
    }

    /// The Git card of the keyboard card's repository at a source: `uncommitted`, or a commit's hash or ref.
    func openGit(_ source: String) {
        let how = Self.how, source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        Task { await open("git", [keyboardPane?.cwd ?? "", source], how) }
    }

    /// The absolute path of a file or folder on the page's machine, nil when there is none: `~` is the home folder,
    /// and a relative path starts at the keyboard card's folder.
    func resolve(_ text: String) async -> String? {
        let script = #"""
        case $1 in "~"|"~/"*) p=$HOME${1#"~"} ;; /*) p=$1 ;; *) p=${2:-$HOME}/$1 ;; esac
        [ -e "$p" ] && printf '%s' "$p"
        """#
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = await (try? store.machine.exec().output(["sh", "-c", script, "sh", text, keyboardPane?.cwd ?? ""]))
        return path.flatMap { $0.isEmpty ? nil : URL(filePath: $0).standardized.path }
    }

    private static var how: Opening {
        NSApp.currentEvent?.modifierFlags.contains(.option) == true ? .side : .tab
    }

    /// `ovvi open`'s kind and argument for the words, opened from the keyboard card; a refusal is a notice.
    private func open(_ first: String, _ words: [String], _ how: Opening) async {
        let pane = keyboardPane
        let call = AgentCall(store: store, pane: pane?.id ?? "", cwd: pane?.cwd ?? "/", id: "", args: [])
        do {
            let (plugin, arg) = try await call.opening(first, words)
            await open(plugin, arg: arg, from: pane?.terminalID ?? "", how: how)
        } catch {
            await store.show(Notice(text: (error as? AgentError)?.message ?? error.localizedDescription,
                                    tone: .warning))
        }
    }
}
