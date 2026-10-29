import AppKit
import HerdrKit
import UniformTypeIdentifiers

/// The file of a File, Markdown or Preview card (phase 42's spec, items 1 to 3): read for its page, saved by its
/// hash, and watched while the card shows.
extension WebCard {
    /// The page's `read` (`web/src/lib/bridge.ts`): the text to edit, the bytes to show, or the info view's facts;
    /// keeps the hash a save checks.
    func read() async -> (Any?, String?) {
        do {
            let (reply, hash) = try await contents()
            self.hash = hash
            return (reply, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// The page's `save`: the text to disk if the file is still the one read (`hash`; nil overwrites it); else the
    /// toast offers Overwrite or Reload.
    func save(_ text: String, over hash: String?) async {
        guard let store else { return }
        saving = true
        defer { saving = false }
        do {
            self.hash = try await Files.save(Data(text.utf8), to: arg, replacing: hash, exec: store.machine.exec())
            send(["op": "saved"])
        } catch FileError.changed {
            toast = Toast(
                text: "\(name) changed on disk since you opened it.",
                other: ("Overwrite", { [weak self] in Task { await self?.save(text, over: nil) } }),
                main: ("Reload", { [weak self] in Task { await self?.reload() } }),
            )
        } catch {
            toast = Toast(
                text: "Could not save \(name): \(error.localizedDescription)",
                other: ("Close", {}),
                main: ("Try Again", { [weak self] in Task { await self?.save(text, over: hash) } }),
            )
        }
    }

    /// While the card shows (`PluginCard`), so a remote machine is asked every 2 s only then: the Files plugin's page
    /// lists again; a file that changed reloads when clean, and a dirty one gets the toast. A change while the card
    /// was hidden shows when it comes back.
    func watch() async {
        guard ["file", "markdown", "preview", "files"].contains(kind), let store else { return }
        let changes = await Files.watch(arg, exec: store.machine.exec())
        if kind == "files" {
            // What changed while the card was hidden.
            send(["op": "changed"])
            for await _ in changes {
                send(["op": "changed"])
            }
            return
        }
        // Not before the page's first read, nor for the card's own save, nor with a hash a save replaced meanwhile.
        // The hash first: a card shown again reads no file that did not change.
        func check() async {
            let before = hash
            guard before != nil, let now = try? await Files.hash(arg, exec: store.machine.exec()), now != before,
                  !saving, hash == before
            else { return }
            guard dirty else { return await reload() }
            toast = Toast(
                text: "\(name) changed on disk.",
                other: ("Reload", { [weak self] in Task { await self?.reload() } }),
                main: ("Keep Mine", { [weak self] in self?.hash = now }),
            )
        }
        await check()
        for await _ in changes {
            await check()
        }
    }

    private func reload() async {
        guard let (reply, hash) = try? await contents() else { return }
        self.hash = hash
        send(reply.merging(["op": "load"]) { $1 })
    }

    private var name: String {
        (arg as NSString).lastPathComponent
    }

    /// The reply to `read` and the file's hash, nil for the info view. Preview reads only the image types both
    /// variants draw, PDF, audio and video, and sends the info view along for a file the page cannot decode; a
    /// remote file over 4 MiB, or one not in UTF-8, opens read only.
    private func contents() async throws -> (reply: [String: Any], hash: String?) {
        guard let store else { throw HerdrError.failed("Closed") }
        let exec = await store.machine.exec(), ext = (arg as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? .data
        let preview = kind == PluginKind.preview.rawValue
        let shown: [UTType] = [.png, .jpeg, .gif, .webP, .heic, .tiff, .bmp, .svg, .pdf, .audiovisualContent]
        if preview, !shown.contains(where: type.conforms) {
            return try await (["info": info(Files.size(arg, exec: exec), type)], nil)
        }
        do {
            let file = try await Files.read(arg, exec: exec)
            if preview {
                let group = type.conforms(to: .image) ? "image" : type.conforms(to: .audio) ? "audio" : "video"
                let mime = type.preferredMIMEType ?? "\(group)/\(ext)"
                return (
                    ["type": mime, "data": file.data.base64EncodedString(), "fallback": info(file.data.count, type)],
                    file.hash,
                )
            }
            // Not `String(data:encoding:)`, which drops a byte order mark the save would not write back.
            let text = String(validating: file.data, as: UTF8.self)
            let readOnly = text == nil || store.machine.isRemote && file.data.count > Files.remoteEditLimit
            return (["text": text ?? String(decoding: file.data, as: UTF8.self), "readOnly": readOnly], file.hash)
        } catch let FileError.tooLarge(size) {
            return (["info": info(size, type)], nil)
        }
    }

    /// The info view: name, size, kind and the type's icon as a PNG.
    private func info(_ size: Int, _ type: UTType) -> [String: String] {
        var rect = CGRect(x: 0, y: 0, width: 192, height: 192)
        let png = NSWorkspace.shared.icon(for: type).cgImage(forProposedRect: &rect, context: nil, hints: nil)
            .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        return [
            "name": name, "size": size.formatted(.byteCount(style: .file)),
            "kind": type.localizedDescription ?? "Document",
            "icon": "data:image/png;base64,\(png?.base64EncodedString() ?? "")",
        ]
    }
}

extension Plugin {
    /// File and Markdown: an editor, which takes ⌘S and ⌘F.
    var edits: Bool {
        kind == .file || kind == .markdown
    }
}

extension Page {
    /// The File or Markdown card with the keyboard: the menu's Save and Find go to its page.
    var editor: Plugin? {
        editor(keyboardPane)
    }

    /// Find Next (1) or Previous (-1): in the editor's page, else in the terminal's find bar.
    func findStep(_ step: Int, in editor: Plugin?) {
        if let editor {
            editor.web.send(["op": step > 0 ? "findNext" : "findPrevious"])
        } else {
            Task { await find?.step(step) }
        }
    }

    /// The pane's card when it is a File or Markdown card.
    func editor(_ pane: HostStore.Pane?) -> Plugin? {
        pane.flatMap(plugin).flatMap { $0.edits ? $0 : nil }
    }
}
