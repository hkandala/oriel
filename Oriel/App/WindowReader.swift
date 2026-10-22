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

        func makeNSView(context _: Context) -> Reader {
            let reader = Reader()
            reader.pages = pages
            return reader
        }

        func updateNSView(_ reader: Reader, context _: Context) {
            reader.changed = { fullScreen = $0 }
        }

        final class Reader: NSView {
            var changed: (Bool) -> Void = { _ in }
            weak var pages: WindowPages?
            private var observers: [NSObjectProtocol] = []

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                guard let window else { return }
                pages?.window = window
                let center = NotificationCenter.default
                let close = NSWindow.willCloseNotification
                observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pages?.closed() }
                })
                let notifications = [NSWindow.willEnterFullScreenNotification: true,
                                     NSWindow.willExitFullScreenNotification: false]
                for (name, value) in notifications {
                    observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.changed(value) }
                    })
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
        }
    }
#endif
