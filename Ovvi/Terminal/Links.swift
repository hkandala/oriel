import AppKit
import GhosttyTerminal
import HerdrKit
import Observation
import SwiftUI

/// A terminal's links (ui/window#opening-links-and-files): addresses and paths libghostty finds in the text, and OSC 8
/// links. libghostty opens one on ⌘-click; ⌥-click over one opens it to the side.
enum Links {
    struct Target {
        let plugin: PluginManifest, arg: String, line: String?
    }

    /// The link without what the text puts after it: `.,;:!?`, and a closing bracket or quote it did not open, as
    /// GitHub reads `(see https://x.y/a).`.
    static func trimmed(_ text: String) -> String {
        var text = Substring(text)
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        func unopened(_ last: Character) -> Bool {
            let closes = text.count(where: { $0 == last })
            if let open = pairs[last] {
                return text.count(where: { $0 == open }) < closes
            }
            return "\"'".contains(last) && closes % 2 == 1
        }
        while let last = text.last, ".,;:!?".contains(last) || unopened(last) {
            text.removeLast()
        }
        return String(text)
    }

    /// What a link opens with: a web address with the browser (or a plugin for its URLs); a file or folder that is
    /// there on the card's machine (`file:`, absolute, `~`, or from the card's folder; a `:line` after it lands
    /// there) with its default plugin, Markdown in File Explorer's Markdown, HTML on This Mac in the browser. Nil for
    /// anything else: other schemes, and text that only looks like a path (`/reload your open pi`).
    private static func target(_ text: String, store: HostStore, cwd: String) async -> Target? {
        let url = URL(string: text), scheme = Self.scheme(text)
        if scheme == "http" || scheme == "https" {
            return Registry.openers(for: text).first.map { Target(plugin: $0, arg: text, line: nil) }
        }
        guard scheme == nil || scheme == "file" else { return nil }
        var path = scheme == "file" ? url?.path ?? "" : text
        let line = path.firstMatch(of: /:(\d+)(?::\d+)?$/)
        if let line {
            path = String(path[..<line.range.lowerBound])
        }
        guard !path.isEmpty, let found = await there(path, store: store, cwd: cwd) else { return nil }
        let landing = line.map { String($0.1) }
        if !store.machine.isRemote, !found.hasSuffix("/"),
           ["html", "htm"].contains(URL(filePath: found).pathExtension.lowercased())
        {
            return Target(plugin: Registry.browser, arg: URL(filePath: found).absoluteString, line: nil)
        }
        return Registry.openers(for: found).first.map { Target(plugin: $0, arg: found, line: landing) }
    }

    /// A link's scheme, only with `://`: `notes.md:12` is a path and its line.
    private static func scheme(_ text: String) -> String? {
        text.contains("://") ? URL(string: text)?.scheme?.lowercased() : nil
    }

    /// The path's absolute form on the card's machine when a file (or a folder, with its `/`) is there.
    private static func there(_ path: String, store: HostStore, cwd: String) async -> String? {
        let script = #"""
        case $1 in "~"|"~/"*) p=$HOME${1#"~"} ;; /*) p=$1 ;; *) p=$2/$1 ;; esac
        if [ -d "$p" ]; then printf '%s/' "$p"; elif [ -e "$p" ]; then printf '%s' "$p"; fi
        """#
        let found = await (try? store.machine.exec().output(["sh", "-c", script, "sh", path, cwd])) ?? ""
        return found.isEmpty ? nil : PathField.tidy(found) + (found.hasSuffix("/") ? "/" : "")
    }

    /// Opens a link of terminal `terminalID`'s card as every link opens, behind the card. False for one that opens
    /// nothing for sure (a path not on This Mac): a ⌥-click on it is the program's.
    static func open(_ text: String, how: Opening, from terminalID: String, page: Page?) -> Bool {
        guard let page else { return false }
        let text = trimmed(text)
        let cwd = page.store.panes.first { $0.terminalID == terminalID }?.cwd ?? "/"
        guard likely(text, remote: page.store.machine.isRemote, cwd: cwd) else { return false }
        Task {
            guard let target = await target(text, store: page.store, cwd: cwd) else { return }
            await page.open(target.plugin, arg: target.arg, at: target.line, from: terminalID, how: how,
                            background: true)
        }
        return true
    }

    /// The link may open, at once: a web address, a path on This Mac that is there, any path on a remote machine
    /// (`target` asks it).
    private static func likely(_ text: String, remote: Bool, cwd: String) -> Bool {
        let scheme = scheme(text)
        if scheme == "http" || scheme == "https" || remote && scheme == nil {
            return true
        }
        guard scheme == nil else { return scheme == "file" }
        let path = (text.replacing(/:\d+(?::\d+)?$/, with: "") as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path.hasPrefix("/") ? path : "\(cwd)/\(path)")
    }
}

extension PaneSurfaceView {
    /// The link under the event's point, as a ⌘-click there would open it. libghostty reports a link only while ⌘ is
    /// down, so the pointer moves there with ⌘ for a moment; first off the view, since libghostty looks for links
    /// again only on another cell than the last.
    func link(at event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil), top = bounds.height - point.y
        linkSurface?.sendMousePos(x: -1, y: -1, modifiers: .super_)
        hoveredLink = nil
        linkSurface?.sendMousePos(x: point.x, y: top, modifiers: .super_)
        let found = hoveredLink
        linkSurface?.sendMousePos(x: point.x, y: top, modifiers: TerminalInputModifiers(from: event.modifierFlags))
        return found
    }
}

extension PaneSurfaceView: TerminalSurfaceOpenURLDelegate, TerminalSurfaceHoverLinkDelegate {
    /// ⌘-click: a new tab behind the card.
    func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        _ = openLink?(url, .tab)
    }

    /// A pointing hand while ⌘ is down over a link.
    func terminalDidUpdateHoverLink(_ url: String?) {
        hoveredLink = url
        (url == nil ? NSCursor.arrow : .pointingHand).set()
    }
}

/// A terminal card's own menu items, before the pane's: Copy, Paste and Select All on this terminal, not on the
/// keyboard card.
struct TerminalItems: View {
    let view: PaneSurfaceView

    var body: some View {
        edit("Copy", #selector(NSText.copy(_:)))
        edit("Paste", #selector(NSText.paste(_:)))
        edit("Select All", #selector(NSText.selectAll(_:)))
        Divider()
    }

    private func edit(_ title: String, _ action: Selector) -> some View {
        Button(title) { NSApp.sendAction(action, to: view, from: nil) }
    }
}
