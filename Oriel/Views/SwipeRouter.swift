#if os(macOS)
    import AppKit
    import SwiftUI

    /// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one goes to
    /// the scroll view under the pointer (the strip, over a card), so a terminal never sees it; any other goes to the
    /// view under the pointer as usual. Its momentum follows. A wheel picks per event; Shift makes it sideways.
    @MainActor
    enum SwipeRouter {
        /// Once, at launch.
        static func install() {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated { route(event) } ? nil : event
            }
        }

        /// Every window's strip, for wheel clicks; each registers itself.
        fileprivate static let strips = NSHashTable<StripAnchor.Anchor>.weakObjects()
        /// Where the current sideways gesture goes; nil while it goes the usual way.
        private weak static var target: NSScrollView?
        private static var picked = false
        private static var moved = 0.0
        private static var wheeled = Date.distantPast

        /// Whether the event went to a scroll view or turned the strip.
        private static func route(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if event.phase.isEmpty, event.momentumPhase.isEmpty {
                return wheel(event, sideways: abs(deltaX) > abs(deltaY) ? deltaX : 0)
            }
            if event.phase == .began {
                picked = false
                target = nil
                moved = 0
            }
            if !picked {
                moved += abs(deltaX) + abs(deltaY)
                if moved >= 4 {
                    picked = true
                    target = abs(deltaX) > abs(deltaY) ? scrollView(event) : nil
                }
            }
            target?.scrollWheel(with: event)
            return target != nil
        }

        /// A sideways wheel step goes to the scroll view under the pointer; over the strip, a burst of line steps
        /// (a mouse, which would only nudge a paged strip) turns one page.
        private static func wheel(_ event: NSEvent, sideways deltaX: CGFloat) -> Bool {
            guard deltaX != 0, let scrollView = scrollView(event) else { return false }
            if !event.hasPreciseScrollingDeltas,
               let strip = strips.allObjects.first(where: { $0.enclosingScrollView === scrollView })
            {
                if Date.now.timeIntervalSince(wheeled) > 0.3 {
                    strip.step(deltaX > 0 ? -1 : 1)
                }
                wheeled = .now
            } else {
                scrollView.scrollWheel(with: event)
            }
            return true
        }

        /// The innermost scroll view under the pointer that can scroll sideways (its document is wider than its clip
        /// view): over a sidebar page's list, the sidebar's pages; over a card, the strip.
        /// None can (a one-tab strip, one sidebar page): the innermost still takes it, so a terminal never does.
        private static func scrollView(_ event: NSEvent) -> NSScrollView? {
            let innermost = event.window?.contentView?.hitTest(event.locationInWindow)?.enclosingScrollView
            var view = innermost
            while let scrollView = view,
                  (scrollView.documentView?.frame.width ?? 0) <= scrollView.contentView.bounds.width + 0.5
            {
                view = scrollView.enclosingScrollView
            }
            return view ?? innermost
        }
    }

    /// Marks the strip's scroll view for the router, with the page turn for wheels.
    struct StripAnchor: NSViewRepresentable {
        let step: (Int) -> Void

        func makeNSView(context _: Context) -> Anchor {
            Anchor(step: step)
        }

        func updateNSView(_ view: Anchor, context _: Context) {
            view.step = step
        }

        final class Anchor: NSView {
            var step: (Int) -> Void

            init(step: @escaping (Int) -> Void) {
                self.step = step
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if window != nil {
                    SwipeRouter.strips.add(self)
                }
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    }
#endif
