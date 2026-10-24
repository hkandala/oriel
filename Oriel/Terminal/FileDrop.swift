#if os(macOS)
    import AppKit
    import GhosttyTerminal

    /// Drops paste their paths shell-escaped, as Ghostty (herdr's usual terminal) does; an image with no file is saved
    /// as a PNG first. A pane drag carries neither type, so it goes on to the card's drop zones.
    /// ponytail: paths on This Mac; a remote machine needs the files copied there first (as image paste plans).
    extension PaneSurfaceView {
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
            guard !urls.isEmpty else { return false }
            return paste(text: urls.map { Self.escaped($0.path(percentEncoded: false)) }.joined(separator: " "))
        }

        /// Ghostty's `Shell.escape` (libghostty-spm's copy is internal).
        private static func escaped(_ path: String) -> String {
            path.unicodeScalars.reduce(into: "") { text, scalar in
                if "\\ ()[]{}<>\"'`!#$&;|*?\t".unicodeScalars.contains(scalar) {
                    text += "\\"
                }
                text.unicodeScalars.append(scalar)
            }
        }

        /// The dragged image as a PNG in the user's temporary folder (`$TMPDIR`, only the user reads it); the system's
        /// cleanup of temporary files removes it.
        private static func savedImage(_ board: NSPasteboard) -> URL? {
            guard let tiff = NSImage(pasteboard: board)?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return nil }
            let file = URL.temporaryDirectory.appending(path: "oriel-\(UUID().uuidString).png")
            return (try? png.write(to: file)).map { file }
        }
    }
#endif
