import AppKit
import GhosttyTerminal
import HerdrKit
import Observation
import SwiftUI

/// A terminal's links (ui/window#opening-links-and-files): addresses and paths libghostty finds in the text, and OSC 8
/// links. libghostty opens one on ⌘-click; ⌘⌥-click opens it to the side, and the card's menu has the link's opens.
@MainActor @Observable
final class Links {
    static let shared = Links()
    /// With `-recordLinks YES` (e2e), Open in Default Browser keeps its link in `recorded` instead of opening it.
    static let record = UserDefaults.standard.bool(forKey: "recordLinks")
    private(set) var recorded: [String] = []

    struct Target {
        let plugin: PluginManifest, arg: String, line: String?
    }

    /// What a link opens with, and its argument: a web address with the browser (or a plugin for its URLs), a file
    /// path (also `file:`, `~` on This Mac, `./` and `../` from the card's folder, a `:line` after it) with its
    /// default plugin and that line. Nil for anything else (`ftp:`, `mailto:`).
    static func target(_ text: String, remote: Bool, cwd: String?) -> Target? {
        let url = URL(string: text), scheme = url?.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            return Registry.openers(for: text).first.map { Target(plugin: $0, arg: text, line: nil) }
        }
        var path = scheme == "file" ? url?.path ?? "" : text
        if !remote, path.hasPrefix("~/") {
            path = (path as NSString).expandingTildeInPath
        } else if let cwd, path.hasPrefix("./") || path.hasPrefix("../") {
            path = PathField.tidy("\(cwd)/\(path)")
        }
        guard path.hasPrefix("/") else { return nil }
        let line = path.firstMatch(of: /:(\d+)(?::\d+)?$/)
        if let line {
            path = String(path[..<line.range.lowerBound])
        }
        return Registry.openers(for: path).first.map { Target(plugin: $0, arg: path, line: line.map { String($0.1) }) }
    }

    /// Opens a link of terminal `terminalID`'s card as every link opens: ⌘ and ⌥ open behind, Open in front.
    static func open(_ text: String, how: Opening, from terminalID: String, page: Page?) {
        let cwd = page?.store.panes.first { $0.terminalID == terminalID }?.cwd
        guard let page, let target = target(text, remote: page.store.machine.isRemote, cwd: cwd) else { return }
        Task {
            await page.open(target.plugin, arg: target.arg, at: target.line, from: terminalID, how: how,
                            background: how != .here)
        }
    }

    /// Open in Default Browser: web addresses only.
    func openInBrowser(_ text: String) {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        if Self.record {
            recorded.append(text)
        } else {
            NSWorkspace.shared.open(url)
        }
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
        openLink?(url, .tab)
    }

    /// A pointing hand while ⌘ is down over a link.
    func terminalDidUpdateHoverLink(_ url: String?) {
        hoveredLink = url
        (url == nil ? NSCursor.arrow : .pointingHand).set()
    }
}

/// A terminal card's own menu items, before the pane's: over a link (`PaneSurfaceView.menuLink`) its opens, Open in
/// Default Browser for a web address and Copy Link; then Copy, Paste and Select All on this terminal, not on the
/// keyboard card.
struct TerminalItems: View {
    let view: PaneSurfaceView

    var body: some View {
        // Relative paths too (any folder): the open resolves them from the card's.
        let remote = view.store()?.machine.isRemote ?? false
        if let link = view.menuLink, Links.target(link, remote: remote, cwd: "/") != nil {
            Button("Open") { view.openLink?(link, .here) }
            Button("Open in New Tab") { view.openLink?(link, .tab) }
            Button("Open to the Side") { view.openLink?(link, .side) }
            if link.lowercased().hasPrefix("http") {
                Button("Open in Default Browser") { Links.shared.openInBrowser(link) }
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            }
            Divider()
        }
        edit("Copy", #selector(NSText.copy(_:)))
        edit("Paste", #selector(NSText.paste(_:)))
        edit("Select All", #selector(NSText.selectAll(_:)))
        Divider()
    }

    private func edit(_ title: String, _ action: Selector) -> some View {
        Button(title) { NSApp.sendAction(action, to: view, from: nil) }
    }
}
