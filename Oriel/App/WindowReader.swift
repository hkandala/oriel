#if os(macOS)
    import AppKit
    import SwiftUI

    /// The window's AppKit side: whether it is in full screen (or on its way in), from its style and its
    /// notifications, and its close, which ends the window's pages (D66 hand-off). A window macOS restores in full
    /// screen keeps AppKit's empty title bar over the title row (the toolbar's on-hover full screen look holds only
    /// when the user enters), so it leaves full screen again: windows never restore in it.
    struct WindowReader: NSViewRepresentable {
        let pages: WindowPages
        @Binding var fullScreen: Bool
        /// e2e: the run loop turns that drew a traffic light off its place.
        @Binding var lightsOff: Int
        @Binding var lightsLog: String

        func makeNSView(context _: Context) -> Reader {
            let reader = Reader()
            reader.pages = pages
            return reader
        }

        func updateNSView(_ reader: Reader, context _: Context) {
            reader.changed = { fullScreen = $0 }
            reader.lightsOff = { lightsOff = $0 }
            reader.lightsLog = { lightsLog = $0 }
        }

        final class Reader: NSView {
            var changed: (Bool) -> Void = { _ in }
            var lightsOff: (Int) -> Void = { _ in }
            var lightsLog: (String) -> Void = { _ in }
            weak var pages: WindowPages?
            private var observers: [NSObjectProtocol] = []

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stop()
                guard let window else { return }
                pages?.window = window
                let center = NotificationCenter.default
                let close = NSWindow.willCloseNotification
                observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.pages?.closed()
                        // The view may go away without leaving its window first.
                        self?.stop()
                    }
                })
                let notifications = [NSWindow.willEnterFullScreenNotification: true,
                                     NSWindow.willExitFullScreenNotification: false]
                for (name, value) in notifications {
                    observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.changed(value) }
                    })
                }
                // AppKit lays the buttons out again on resizes, key changes and full screen: put them back each time,
                // and once more after its layout (a button moved in its own frame notification goes back).
                let place: @Sendable (Notification) -> Void = { [weak self] note in
                    nonisolated(unsafe) let note = note // probe
                    MainActor.assumeIsolated {
                        self?.trace(note)
                        self?.placeButtons()
                    }
                    DispatchQueue.main.async { self?.placeButtons() }
                }
                for button in buttons(of: window) {
                    observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: button,
                                                        queue: .main, using: place))
                }
                // Leaving full screen, the window still says full screen until it is out.
                observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                                    queue: .main, using: place))
                placeButtons()
                if UserDefaults.standard.bool(forKey: "recordLights") {
                    recordLights()
                }
                // After SwiftUI's update, which may not change state.
                let full = window.styleMask.contains(.fullScreen)
                let restored = AppDelegate.restoredFullScreen.remove(ObjectIdentifier(window)) != nil
                DispatchQueue.main.async { [weak self] in
                    self?.changed(full)
                    if restored {
                        window.toggleFullScreen(nil)
                    }
                }
            }

            private var events: [String]?
            private let start = Date.now

            private func event(_ text: String) {
                guard events != nil else { return }
                events!.append(String(format: "%.3f ", Date.now.timeIntervalSince(start)) + text)
                events = events!.suffix(40)
                lightsLog(events!.joined(separator: "\n"))
            }

            private func trace(_ note: Notification) {
                guard events != nil, let window, let button = note.object as? NSButton else { return }
                let index = buttons(of: window).firstIndex(of: button) ?? -1
                let stack = Thread.callStackSymbols.dropFirst(2).prefix(24).map { line in
                    line.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).prefix(2)
                        .joined(separator: " ")
                }.filter { !$0.contains("Notification") && !$0.contains("CFNotif") && !$0.contains("_CF") }
                event("b\(index) \(button.frame.origin) | " + stack.joined(separator: " < "))
            }

            /// e2e (`-recordLights YES`): counts the run loop turns that drew a traffic light off its place.
            private func recordLights() {
                events = []
                var count = 0
                // After Core Animation's commit (order 2000000): what this turn drew.
                let turn = CFRunLoopActivity.beforeWaiting.rawValue
                let observer = CFRunLoopObserverCreateWithHandler(nil, turn, true, Int.max) { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.window,
                              !window.styleMask.contains(.fullScreen) else { return }
                        let off = self.buttons(of: window).enumerated().filter { index, button in
                            guard let superview = button.superview else { return false }
                            let center = superview.convert(button.frame, to: nil)
                            return abs(center.midX - TitleBar.height / 2 - CGFloat(index) * 23) > 0.5
                                || abs(window.frame.height - center.midY - TitleBar.height / 2) > 0.5
                        }
                        if !off.isEmpty {
                            count += 1
                            self.lightsOff(count)
                            self.event("OFF \(off.map(\.offset)) \(off.map(\.element.frame.origin))")
                        }
                    }
                }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }

            private func stop() {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
            }

            private func buttons(of window: NSWindow) -> [NSButton] {
                [.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
            }

            /// Rex's traffic lights: centered on the title row at 23, 46 and 69 pt from the left (the compact
            /// toolbar centers them at 19, 20). Public AppKit: plain frame changes of the standard buttons.
            private func placeButtons() {
                guard let window, !window.styleMask.contains(.fullScreen) else { return }
                for (index, button) in buttons(of: window).enumerated() {
                    guard let superview = button.superview else { continue }
                    let size = button.frame.size, center = TitleBar.height / 2
                    let frame = NSRect(x: center + CGFloat(index) * 23 - size.width / 2,
                                       y: window.frame.height - center - size.height / 2, width: size.width,
                                       height: size.height)
                    let origin = superview.convert(frame, from: nil).origin
                    // Only a real move: setting the frame posts the notification that calls this.
                    if abs(button.frame.minX - origin.x) > 0.1 || abs(button.frame.minY - origin.y) > 0.1 {
                        button.setFrameOrigin(origin)
                    }
                }
            }
        }
    }
#endif
