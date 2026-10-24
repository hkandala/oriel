#if os(macOS)
    import AppKit
    import GhosttyTerminal

    /// Files and images dropped on a terminal paste their paths, as a drop on Ghostty does (herdr only passes on what
    /// its terminal pastes): each path backslash-escaped with Ghostty's `Shell.escape` characters, joined by spaces, in
    /// one bracketed paste. An image with no file (from a browser, a screenshot thumbnail) is written to a new
    /// temporary
    /// folder first. A pane drag carries neither type, so it goes on to the card's drop zones.
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

        static func escaped(_ path: String) -> String {
            path.unicodeScalars.reduce(into: "") { text, scalar in
                if "\\ ()[]{}<>\"'`!#$&;|*?\t".unicodeScalars.contains(scalar) {
                    text += "\\"
                }
                text.unicodeScalars.append(scalar)
            }
        }

        /// The dragged image as a PNG in a new folder only the user can read; the system's cleanup of temporary files
        /// removes it.
        private static func savedImage(_ board: NSPasteboard) -> URL? {
            guard let tiff = NSImage(pasteboard: board)?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return nil }
            let folder = URL.temporaryDirectory.appending(path: "oriel-\(UUID().uuidString)")
            let file = folder.appending(path: "image.png")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try png.write(to: file)
                return file
            } catch {
                return nil
            }
        }
    }
#endif
