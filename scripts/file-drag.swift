// A file's icon in a small window of its own, for the file drop tests: a drag from Finder now and then started nothing
// on CI. Shows the icon at x y (screen points, top left) and drags it to tx ty, both points in an Ovvi window, as
// scripts/drag.swift posts its drags. Exits 0 when a drop took the file, 1 when the drop was refused, 2 when no drag
// ended within 10 s.
// Usage: file-drag <path> <x> <y> <tx> <ty>
import AppKit

let args = CommandLine.arguments.dropFirst(2).compactMap { Double($0) }
guard args.count == 4 else { fatalError("usage: file-drag <path> <x> <y> <tx> <ty>") }
let url = URL(filePath: CommandLine.arguments[1])
let start = CGPoint(x: args[0], y: args[1]), end = CGPoint(x: args[2], y: args[3])
let ovvi = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).contains {
    let bounds = ($0[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .null
    return $0[kCGWindowLayer as String] as? Int == 0 && $0[kCGWindowOwnerName as String] as? String == "Ovvi"
        && bounds.contains(start) && bounds.contains(end)
}

guard ovvi else { fatalError("not both of \(start) and \(end) in an Ovvi window") }
/// Signaled when the drag session begins.
let began = DispatchSemaphore(value: 0)

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

    func draggingSession(_: NSDraggingSession, willBeginAt _: NSPoint) {
        began.signal()
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
// Non-activating: the app under test stays the active one. Floating: over Ovvi's window.
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

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

/// Presses on the icon once the window server shows the panel (`orderFrontRegardless` returns before: a press then
/// lands on Ovvi's window), and moves on only once the drag session began: a busy runner began it after a release
/// posted on a timer, and that session never ended.
func drag() {
    CGWarpMouseCursorPosition(start)
    Thread.sleep(forTimeInterval: 0.3)
    post(.leftMouseDown, start)
    Thread.sleep(forTimeInterval: 0.3)
    post(.leftMouseDragged, CGPoint(x: start.x + 8, y: start.y))
    guard began.wait(timeout: .now() + 5) == .success else {
        post(.leftMouseUp, start)
        fputs("no drag began: the press did not start one\n", stderr)
        exit(2)
    }
    for step in 1 ... 20 {
        let part = Double(step) / 20
        post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * part, y: start.y + (end.y - start.y) * part))
        Thread.sleep(forTimeInterval: 0.015)
    }
    Thread.sleep(forTimeInterval: 0.5)
    post(.leftMouseUp, end)
}

func pressWhenShown() {
    let shown = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
        .contains { $0[kCGWindowNumber as String] as? Int == panel.windowNumber }
    guard shown else { return DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: pressWhenShown) }
    Thread.detachNewThread(drag)
}

DispatchQueue.main.async(execute: pressWhenShown)

DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    fputs("no drag ended\n", stderr)
    exit(2)
}

app.run()
