import AppKit
import SwiftUI

/// Where floating windows open: SwiftUI places a new one at the frame asked for with it (`defaultWindowPlacement`),
/// so nothing sizes it after. (The app set the frame once the window showed, and SwiftUI's default size sometimes came
/// after it: a replaced pane's window came back 46 pt short on CI.)
@MainActor
enum FloatFrames {
    /// Each floated terminal's window.
    static let windows = NSMapTable<NSString, NSWindow>.strongToWeakObjects()
    /// The frame of the floating window asked for last, until SwiftUI places it.
    private static var next: NSRect?

    /// Opens the pane's floating window, or brings it to the front: a new one at `frame` (a replaced pane's old
    /// window's), else where it was last (AppKit's saved frame), else over its main window.
    static func open(_ floating: Floating, over main: NSWindow?, frame: NSRect? = nil, with open: OpenWindowAction?) {
        if windows.object(forKey: floating.terminalID as NSString) == nil {
            next = frame ?? saved(floating.terminalID) ?? main.map(frame(over:))
        }
        open?(id: "float", value: floating)
    }

    /// `next`, in the screen's top-left based points that `WindowPlacement` takes.
    static func placement() -> WindowPlacement {
        defer { next = nil }
        guard let frame = next, let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main else { return WindowPlacement() }
        return WindowPlacement(CGPoint(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY),
                               size: frame.size)
    }

    /// A new floating window: 60 % of its main window's width and 75 % of its height, at least 720 × 460 pt,
    /// centered over it. AppKit keeps it on the screen.
    static func frame(over main: NSWindow) -> NSRect {
        let width = max(720, main.frame.width * 0.6), height = max(460, main.frame.height * 0.75)
        let frame = NSRect(x: main.frame.midX - width / 2, y: main.frame.midY - height / 2, width: width,
                           height: height)
        return main.constrainFrameRect(frame, to: main.screen)
    }

    /// AppKit's saved frame for the terminal's window (`setFrameAutosaveName`): "x y width height …".
    private static func saved(_ terminalID: String) -> NSRect? {
        let parts = UserDefaults.standard.string(forKey: "NSWindow Frame float \(terminalID)")?
            .split(separator: " ").compactMap { Double($0) } ?? []
        return parts.count >= 4 ? NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
    }
}

struct FloatReader: NSViewRepresentable {
    let terminalID: String
    let pinned: Bool
    let closed: () -> Void

    func makeNSView(context _: Context) -> Reader {
        let reader = Reader()
        reader.terminalID = terminalID
        return reader
    }

    func updateNSView(_ reader: Reader, context _: Context) {
        reader.closed = closed
        // Above every app's windows and on every Space, like picture in picture.
        reader.window?.level = pinned ? .floating : .normal
        let onTop: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if pinned {
            reader.window?.collectionBehavior.formUnion(onTop)
        } else {
            reader.window?.collectionBehavior.subtract(onTop)
        }
    }

    final class Reader: TrafficLights {
        var closed: () -> Void = {}
        var terminalID = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Placed by SwiftUI (`FloatFrames`); AppKit keeps the frame for the next time the pane floats.
            // ponytail: one defaults key per terminal ever floated; prune them if that ever matters.
            FloatFrames.windows.setObject(window, forKey: terminalID as NSString)
            window.setFrameAutosaveName("float \(terminalID)")
            let center = NotificationCenter.default, close = NSWindow.willCloseNotification
            observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closed()
                    self?.stop()
                }
            })
        }
    }
}
