#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import HerdrKit

    /// Drops paste their paths shell-escaped, as Ghostty (herdr's usual terminal) does; an image with no file is saved
    /// as a PNG first, or received from its source (a browser's image may be only a file promise). A pane drag carries
    /// none of these types, so it goes on to the card's drop zones.
    /// ponytail: paths on This Mac; a remote machine needs the files copied there first (as image paste plans).
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
                return paste(text: urls.map { Self.escaped($0.path(percentEncoded: false)) }.joined(separator: " "))
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
                    let path = Self.escaped(url.path(percentEncoded: false))
                    MainActor.assumeIsolated { _ = self?.paste(text: path) }
                },
            )
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
        /// only its shell (D41). ponytail: This Mac only; remote machines need another picker.
        func choosePath(directory: Bool) async {
            guard let pane = keyboardPane, let client = store.client, let window = NSApp.keyWindow else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = !directory
            panel.directoryURL = await (try? client.pane(pane.id).cwd).map { URL(filePath: $0) }
            guard await panel.beginSheetModal(for: window) == .OK, let path = panel.url?.path(percentEncoded: false)
            else { return }
            let quoted = "'" + path.replacing("'", with: #"'\''"#) + "'"
            if directory {
                do {
                    guard try await client.program(pane.id)?.isShell == true else {
                        await store.show(Notice(text: "A program is running in the pane", tone: .warning))
                        return
                    }
                } catch {
                    await store.show(Notice(text: error.localizedDescription))
                    return
                }
            }
            await store.write { client in
                try await client.sendInput(directory ? "cd -- \(quoted)" : quoted, keys: directory ? ["enter"] : [],
                                           pane: pane.id)
            }
        }
    }
#endif
