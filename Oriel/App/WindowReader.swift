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

        func makeNSView(context _: Context) -> Reader {
            let reader = Reader()
            reader.pages = pages
            return reader
        }

        func updateNSView(_ reader: Reader, context _: Context) {
            reader.changed = { fullScreen = $0 }
            reader.lightsOff = { lightsOff += 1 }
        }

        final class Reader: TrafficLights {
            var changed: (Bool) -> Void = { _ in }
            var lightsOff: () -> Void = {}
            weak var pages: WindowPages?
            /// e2e: the `-recordLights` counter.
            private var lightsObserver: CFRunLoopObserver?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
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

            /// e2e (`-recordLights YES`): counts the run loop turns that drew a traffic light off its place.
            private func recordLights() {
                // After Core Animation's commit (order 2000000), which runs before waiting and on a loop's exit: what
                // this turn drew. Before waiting alone missed the flicker.
                let turn = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
                let observer = CFRunLoopObserverCreateWithHandler(nil, turn, true, Int.max) { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        if let self, !self.moved().isEmpty {
                            self.lightsOff()
                        }
                    }
                }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                lightsObserver = observer
            }

            override func stop() {
                super.stop()
                lightsObserver.map(CFRunLoopObserverInvalidate)
                lightsObserver = nil
            }
        }
    }

    /// Rex's traffic lights: centered on a title row of `TitleBar.height` at 23, 46 and 69 pt from the left (the
    /// compact toolbar centers them at 19, 20), in the main window and the floating ones. Public AppKit: plain frame
    /// changes of the standard buttons.
    class TrafficLights: NSView {
        var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            // AppKit lays the buttons out again on title changes (each tab or workspace switch), resizes, key
            // changes and full screen. They go back in this view's layout, after AppKit's tiling and before the
            // draw: a move from the frame notification is dropped for the button AppKit is moving
            // (`setFrameOrigin:ignoreRentry:`), and one on the next turn came after a draw (phase 24).
            let place: @Sendable (Notification) -> Void = { [weak self] _ in
                MainActor.assumeIsolated { self?.needsLayout = true }
            }
            let center = NotificationCenter.default
            for button in buttons(of: window) {
                observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: button,
                                                    queue: .main, using: place))
            }
            // Leaving full screen, the window still says full screen until it is out.
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                                queue: .main, using: place))
            placeButtons()
        }

        override func layout() {
            super.layout()
            placeButtons()
        }

        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        private func buttons(of window: NSWindow) -> [NSButton] {
            [.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        }

        private func placeButtons() {
            for (button, origin) in moved() {
                button.setFrameOrigin(origin)
            }
        }

        /// The buttons off their place, each with its place in its superview; none in full screen.
        func moved() -> [(button: NSButton, origin: NSPoint)] {
            guard let window, !window.styleMask.contains(.fullScreen) else { return [] }
            return buttons(of: window).enumerated().compactMap { index, button in
                guard let superview = button.superview else { return nil }
                let size = button.frame.size, center = TitleBar.height / 2
                let frame = NSRect(x: center + CGFloat(index) * 23 - size.width / 2,
                                   y: window.frame.height - center - size.height / 2, width: size.width,
                                   height: size.height)
                let origin = superview.convert(frame, from: nil).origin
                // Only a real move: setting the frame posts the notification that leads here.
                let off = abs(button.frame.minX - origin.x) > 0.1 || abs(button.frame.minY - origin.y) > 0.1
                return off ? (button, origin) : nil
            }
        }
    }
#endif
