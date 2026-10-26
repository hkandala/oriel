// A file dragged from a small window of its own to a point on the screen, for the file drop test: a drag from Finder
// now and then started nothing on CI (phase 31). Shows the file's icon at x y (screen points, top left), presses there
// and drags to tx ty as scripts/drag.swift does; exits 0 when a drop took the file, 1 when the drop was refused.
// Usage: file-drag <path> <x> <y> <tx> <ty>
import AppKit

let args = CommandLine.arguments.dropFirst(2).compactMap { Double($0) }
guard CommandLine.arguments.count == 6, args.count == 4 else { fatalError("usage: file-drag <path> <x> <y> <tx> <ty>") }
let url = URL(filePath: CommandLine.arguments[1])
let (start, target) = (CGPoint(x: args[0], y: args[1]), CGPoint(x: args[2], y: args[3]))

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

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let height = NSScreen.screens[0].frame.height, size = 64.0
// Non-activating: the app under test stays the active one.
let panel = NSPanel(
    contentRect: NSRect(x: start.x - size / 2, y: height - start.y - size / 2, width: size, height: size),
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

// Off the main thread, which runs the drag.
Thread {
    Thread.sleep(forTimeInterval: 0.5)
    CGWarpMouseCursorPosition(start)
    post(.leftMouseDown, start)
    Thread.sleep(forTimeInterval: 0.3)
    for step in 1 ... 20 {
        let part = Double(step) / 20
        post(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * part,
                                        y: start.y + (target.y - start.y) * part))
        Thread.sleep(forTimeInterval: 0.015)
    }
    Thread.sleep(forTimeInterval: 0.5)
    post(.leftMouseUp, target)
    Thread.sleep(forTimeInterval: 5)
    fputs("no drag ended: the press did not start one\n", stderr)
    exit(2)
}.start()
app.run()
