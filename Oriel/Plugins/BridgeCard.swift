import AppKit
import HerdrKit
import os
import SwiftUI
import UniformTypeIdentifiers

/// The page's calls that the app answers itself: opens, the toast, the native menu, Choose Folder…, SF Symbols and
/// the clipboard.
extension Bridge {
    func card(_ name: String, _ args: [String: Any], _ plugin: Plugin) async throws -> Any? {
        switch name {
        case "open": try open(args, plugin)
        case "toast":
            let buttons = args["buttons"] as? [String]
            show(
                args["text"] as? String ?? "",
                buttons: buttons?.count == 2 ? buttons : nil,
                id: args["id"] as? Int ?? 0,
            )
        case "menu.show": return menu(args["items"] as? [Any] ?? [], in: plugin.web.view)
        case "pick.folder": return await folder(from: args["from"] as? String ?? plugin.web.arg, plugin)
        case "symbol":
            let name = args["name"] as? String ?? ""
            guard let url = Self.symbol(name, size: args["size"] as? Double ?? 16) else {
                throw PluginError("notFound", "No symbol \(name)")
            }
            return url
        case "clipboard.write":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(args["text"] as? String ?? "", forType: .string)
        default: throw PluginError("failed", "No call \(name)")
        }
        return nil
    }

    /// The facts HerdrKit reads, with the system's icon of the kind as a PNG data URL.
    func info(_ args: [String: Any]) async throws -> Any {
        var info = try await JSONSerialization.jsonObject(with: calls("files.info", args)) as? [String: Any] ?? [:]
        let type = (info.removeValue(forKey: "type") as? String).flatMap { UTType($0) } ?? .data
        var rect = CGRect(x: 0, y: 0, width: 192, height: 192)
        let png = NSWorkspace.shared.icon(for: type).cgImage(forProposedRect: &rect, context: nil, hints: nil)
            .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        info["icon"] = "data:image/png;base64,\(png?.base64EncodedString() ?? "")"
        return info
    }

    /// In the card (a place of this plugin), a new tab after the card's tab (the default), or a pane to its side.
    private func open(_ args: [String: Any], _ plugin: Plugin) throws {
        guard let arg = args["arg"] as? String else { throw PluginError("failed", "arg is missing") }
        let how: Opening = switch args["how"] as? String {
        case "card": .here
        case "side": .side
        default: .tab
        }
        try plugin.web.open?(opener(arg, args["plugin"] as? String), arg, args["at"] as? String, how)
    }

    /// The toast the page waits on goes: its promise resolves with no button.
    func dropToast() {
        if let toast {
            event("toast", ["id": toast])
            self.toast = nil
        }
    }

    /// The page's toast, replacing one it waits on.
    func show(_ text: String, buttons: [String]?, id: Int) {
        guard let web = plugin?.web else { return }
        dropToast()
        toast = id
        let picked = { [weak self] (title: String) in
            guard let self, toast == id else { return }
            toast = nil
            event("toast", ["id": id, "button": title])
        }
        let main = buttons?.last ?? "OK"
        web.toast = Toast(text: text, other: buttons?.first.map { title in (title, { picked(title) }) },
                          main: (main, { picked(main) }))
    }

    /// The plugin an open names, else the browser for a web address, the first plugin that opens folders for a
    /// folder, or a file's default plugin.
    private func opener(_ arg: String, _ id: String?) throws -> PluginManifest {
        let scheme = URL(string: arg)?.scheme?.lowercased()
        let found = id.map(Registry.plugin) ?? (scheme == "http" || scheme == "https" ? Registry.browser
            : arg.hasSuffix("/") ? Registry.all.first { $0.opens.folders } : Registry.openers(arg).first)
        guard let found else { throw PluginError("notFound", "No plugin opens \(arg)") }
        return found
    }

    /// The native menu at the pointer: items (`{ value, title, symbol }`), section headings (`{ title }`) and
    /// dividers (`"-"`). The picked item's value; nil when none was picked.
    private func menu(_ items: [Any], in view: NSView) -> String? {
        guard let window = view.window else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        var picked: String?
        for item in items {
            guard let item = item as? [String: Any], let title = item["title"] as? String else {
                menu.addItem(.separator())
                continue
            }
            guard let value = item["value"] as? String else {
                menu.addItem(.sectionHeader(title: title))
                continue
            }
            let action = MenuAction { picked = value }
            let entry = menu.addItem(withTitle: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            entry.target = action
            entry.representedObject = action
            entry.image = (item["symbol"] as? String).flatMap { NSImage(
                systemSymbolName: $0,
                accessibilityDescription: nil,
            ) }
        }
        // Returns once the menu closed, after the picked item's action.
        menu.popUp(positioning: nil, at: view.convert(window.mouseLocationOutsideOfEventStream, from: nil), in: view)
        return picked
    }

    /// Choose Folder…: This Mac's folder panel; a remote machine's folder field, the path as the machine resolves it
    /// (`~` its home folder). Nil when cancelled or no folder.
    private func folder(from start: String, _ plugin: Plugin) async -> String? {
        guard let store = plugin.web.store, let window = plugin.web.view.window else { return nil }
        if !store.machine.isRemote {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = URL(filePath: start)
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return nil }
            let path = url.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        let alert = NSAlert()
        alert.messageText = "Go to Folder"
        alert.informativeText = "A folder on \(store.machine.name)"
        let field = NSTextField(string: start)
        field.frame.size.width = 280
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return nil }
        let script = #"case $1 in "~"*) set -- "$HOME${1#\~}";; esac; cd "$1" 2>/dev/null && pwd -P"#
        guard let channel = try? await store.machine.exec().run(["sh", "-c", script, "sh", field.stringValue])
        else { return nil }
        channel.closeInput()
        let path = await channel.lines.reduce("", +)
        return await channel.exit().status == 0 && path.hasPrefix("/") ? path : nil
    }

    /// An SF Symbol, `size` points tall at 2x, as a PNG data URL: black on clear, for a mask.
    static func symbol(_ name: String, size: Double) -> String? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 2, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration), let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}

extension CommandList {
    /// The manifest's commands of the plugin card with the keyboard, in the menu bar and the palette
    /// (manifest#commands):
    /// gone elsewhere, so they swallow no key. A key the app already uses is left off, once in the log.
    static func plugin(_ plugin: Plugin?, besides list: [Command]) -> [Command] {
        guard let plugin, let bridge = plugin.web.bridge else { return [] }
        let taken = Set(list.compactMap(\.key))
        return plugin.manifest.commands.map { command in
            let change = bridge.commands[command.id] ?? [:]
            var key = command.key.flatMap(shortcut)
            if let shown = key, taken.contains(shown) {
                key = nil
                if logged.insert("\(plugin.manifest.id) \(command.id)").inserted {
                    let text = "\(plugin.manifest.id): \(command.key ?? "") of \(command.id) is the app's"
                    Logger(subsystem: "dev.hkandala.oriel", category: "plugins").error("\(text, privacy: .public)")
                }
            }
            let section: Command.Section = switch command.menu {
            case "file": .file
            case "edit": .edit
            default: .view
            }
            let pick = { bridge.event("control", ["id": command.id]) }
            return Command(section: section, title: change["title"] as? String ?? command.title, key: key,
                           symbol: command.symbol, enabled: change["enabled"] as? Bool ?? true,
                           checked: change["checked"] as? Bool ?? command.checked, action: pick)
        }
    }

    @MainActor private static var logged = Set<String>()

    /// `cmd+e`, `cmd+shift+k`, `cmd+option+[`.
    private static func shortcut(_ text: String) -> KeyboardShortcut? {
        let parts = text.lowercased().split(separator: "+")
        guard let last = parts.last, last.count == 1, let char = last.first else { return nil }
        let modifiers: [Substring: EventModifiers] = ["cmd": .command, "shift": .shift, "option": .option,
                                                      "alt": .option, "ctrl": .control, "control": .control]
        return KeyboardShortcut(KeyEquivalent(char), modifiers: parts.dropLast().reduce(into: []) {
            $0.insert(modifiers[$1] ?? [])
        })
    }
}
