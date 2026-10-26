import AppKit
import GhosttyTerminal
import HerdrKit

/// Drops paste their paths shell-escaped, as Ghostty (herdr's usual terminal) does; an image with no file is saved
/// as a PNG first, or received from its source (a browser's image may be only a file promise). On a remote machine
/// the files are copied there first and their copies' paths pasted (`Exec.upload`). A pane drag carries none of these
/// types, so it goes on to the card's drop zones.
extension PaneSurfaceView {
    static let dropTypes: [NSPasteboard.PasteboardType] = [.fileURL, .tiff, .png]
        + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }

    override func draggingEntered(_: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        var urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        if urls.isEmpty, let image = Self.savedImage(board) {
            urls = [image]
        }
        if !urls.isEmpty {
            return drop(urls)
        }
        // ponytail: each promised file pastes on its own; join them when a source promises several.
        let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]
        guard let promise = promises?.first, let folder = Self.newFolder() else { return false }
        promise.receivePromisedFiles(
            atDestination: folder,
            options: [:],
            operationQueue: .main,
            reader: { [weak self] url, error in
                guard error == nil else { return }
                MainActor.assumeIsolated { _ = self?.drop([url]) }
            },
        )
        return true
    }

    /// Pastes the files' paths, joined by spaces; on a remote machine, the paths of their copies there, once all are
    /// copied. A copy that fails shows why, and nothing is pasted.
    private func drop(_ urls: [URL]) -> Bool {
        guard let store = store(), store.machine.isRemote else {
            return paste(text: urls.map { Self.escaped($0.path(percentEncoded: false)) }.joined(separator: " "))
        }
        Task {
            let exec = await store.machine.exec()
            do {
                var paths: [String] = []
                for url in urls {
                    try await paths.append(Self.escaped(exec.upload(url)))
                }
                _ = paste(text: paths.joined(separator: " "))
            } catch {
                await store.show(Notice(text: error.localizedDescription))
            }
        }
        return true
    }

    /// Ghostty's `Shell.escape` (libghostty-spm's copy is internal). A path with a line break is quoted instead: a
    /// shell without bracketed paste would run the line after it.
    private static func escaped(_ path: String) -> String {
        if path.contains(where: \.isNewline) {
            return "'" + path.replacing("'", with: #"'\''"#) + "'"
        }
        return path.unicodeScalars.reduce(into: "") { text, scalar in
            if "\\ ()[]{}<>\"'`!#$&;|*?\t".unicodeScalars.contains(scalar) {
                text += "\\"
            }
            text.unicodeScalars.append(scalar)
        }
    }

    /// The dragged image as a PNG.
    private static func savedImage(_ board: NSPasteboard) -> URL? {
        guard let tiff = NSImage(pasteboard: board)?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              let file = newFolder()?.appending(path: "image.png")
        else { return nil }
        return (try? png.write(to: file)).map { file }
    }

    /// A new folder in the user's temporary folder (`$TMPDIR`, only the user reads it), so a promised file keeps
    /// its name; the system's cleanup of temporary files removes it.
    private static func newFolder() -> URL? {
        let folder = URL.temporaryDirectory.appending(path: "oriel-\(UUID().uuidString)")
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true))
            .map { folder }
    }
}

extension Page {
    /// Go to Directory (`directory`, a `cd`) or Insert Path: the system panel at the keyboard card's folder, fresh
    /// from herdr, then the chosen path typed into the card, quoted. Go to Directory asks again that the card runs
    /// only its shell (D41). On a remote machine Insert Path picks a file of This Mac and types the path of its copy
    /// there, as a drop does. ponytail: Go to Directory is This Mac's only; a remote machine needs another picker.
    func choosePath(directory: Bool) async {
        guard let pane = keyboardPane, let client = store.client, let window = NSApp.keyWindow else { return }
        let remote = store.machine.isRemote
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory || !remote
        panel.canChooseFiles = !directory
        if !remote {
            panel.directoryURL = await (try? client.pane(pane.id).cwd).map { URL(filePath: $0) }
        }
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        var path = url.path(percentEncoded: false)
        do {
            if remote, !directory {
                path = try await store.machine.exec().upload(url)
            }
            if directory, try await client.program(pane.id)?.isShell != true {
                await store.show(Notice(text: "A program is running in the pane", tone: .warning))
                return
            }
        } catch {
            await store.show(Notice(text: error.localizedDescription))
            return
        }
        let quoted = "'" + path.replacing("'", with: #"'\''"#) + "'"
        await store.write { client in
            try await client.sendInput(directory ? "cd -- \(quoted)" : quoted, keys: directory ? ["enter"] : [],
                                       pane: pane.id)
        }
    }
}
