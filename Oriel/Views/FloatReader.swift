import AppKit
import SwiftUI

/// Each floated terminal's window, and a replaced pane's frame for its new pane's window (`Page.floatReplaced`).
@MainActor
enum FloatFrames {
    static let windows = NSMapTable<NSString, NSWindow>.strongToWeakObjects()
    static var handed: [String: NSRect] = [:]
}

struct FloatReader: NSViewRepresentable {
    let terminalID: String
    /// The main window that floated the pane, for a new window's frame.
    weak var main: NSWindow?
    let pinned: Bool
    let closed: () -> Void

    func makeNSView(context _: Context) -> Reader {
        let reader = Reader()
        reader.terminalID = terminalID
        reader.main = main
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
        weak var main: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // AppKit keeps the frame for the next time the pane floats. ponytail: one defaults key per terminal
            // ever floated; prune them if that ever matters.
            let name = "float \(terminalID)"
            FloatFrames.windows.setObject(window, forKey: terminalID as NSString)
            if let frame = FloatFrames.handed.removeValue(forKey: terminalID) {
                window.setFrame(frame, display: false)
            } else if !window.setFrameUsingName(name), let main {
                window.setFrame(Self.frame(over: main), display: false)
            }
            window.setFrameAutosaveName(name)
            // SwiftUI can still give a new window its default size after this (a replaced pane's window came back
            // 46 pt short on CI): the frame again on the next turn.
            let placed = window.frame
            DispatchQueue.main.async { [weak window] in
                if let window, window.frame != placed {
                    window.setFrame(placed, display: true)
                }
            }
            let center = NotificationCenter.default, close = NSWindow.willCloseNotification
            observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closed()
                    self?.stop()
                }
            })
        }

        /// A new floating window: 60 % of its main window's width and 75 % of its height, at least 720 × 460 pt,
        /// centered over it. AppKit keeps it on the screen.
        static func frame(over main: NSWindow) -> NSRect {
            let width = max(720, main.frame.width * 0.6), height = max(460, main.frame.height * 0.75)
            let frame = NSRect(x: main.frame.midX - width / 2, y: main.frame.midY - height / 2, width: width,
                               height: height)
            return main.constrainFrameRect(frame, to: main.screen)
        }
    }
}
