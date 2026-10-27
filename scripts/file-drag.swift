// A file's icon in a small window of its own, for the file drop test: a drag from Finder now and then started nothing
// on CI. Shows the icon at x y (screen points, top left); a drag from it (scripts/drag.swift, posted by the
// e2e helper) carries the file. Exits 0 when a drop took the file, 1 when the drop was refused, 2 when no drag ended
// within 10 s. Prints "up" once its window is up.
// Usage: file-drag <path> <x> <y>
import AppKit

let args = CommandLine.arguments.dropFirst(2).compactMap { Double($0) }
guard args.count == 2 else { fatalError("usage: file-drag <path> <x> <y>") }
let url = URL(filePath: CommandLine.arguments[1])

final class Source: NSView, NSDraggingSource {
    private var dragging = false

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: layer?.contents)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        exit(operation.isEmpty ? 1 : 0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let height = NSScreen.screens[0].frame.height, size = 64.0
// Non-activating: the app under test stays the active one. Floating: drag.swift still finds Oriel's window under it.
let panel = NSPanel(
    contentRect: NSRect(x: args[0] - size / 2, y: height - args[1] - size / 2, width: size, height: size),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false,
)
panel.level = .floating
let source = Source()
source.wantsLayer = true
source.layer?.contents = NSWorkspace.shared.icon(forFile: url.path)
panel.contentView = source
panel.orderFrontRegardless()
// The helper drags once this line comes, not after a fixed wait: a press before the window is up starts no drag.
DispatchQueue.main.async {
    print("up")
    fflush(stdout)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    fputs("no drag ended: the press did not start one\n", stderr)
    exit(2)
}

app.run()
