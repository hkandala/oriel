#if os(macOS)
    import AppKit
    import SwiftUI

    /// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one goes to
    /// the scroll view under the pointer (the strip, over a card), so a terminal never sees it; any other goes to the
    /// view under the pointer as usual. Its momentum follows. A wheel picks per event; Shift makes it sideways. A
    /// scroll view whose anchor takes the lift (the sidebar's sessions) can take the gesture's end and its momentum as
    /// one call with the fingers' speed instead.
    @MainActor
    enum SwipeRouter {
        /// Once, at launch.
        static func install() {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated { route(event) } ? nil : event
            }
        }

        /// Every window's strip (for wheel clicks) and sidebar pages (for the lift); each registers itself.
        fileprivate static let anchors = NSHashTable<ScrollAnchor.Anchor>.weakObjects()
        /// Where the current sideways gesture goes; nil while it goes the usual way.
        private weak static var target: NSScrollView?
        private static var picked = false
        private static var moved = 0.0
        private static var wheeled = Date.distantPast
        /// The gesture's sideways speed in the content's points a second, from its last moves.
        private static var speed = 0.0, last = 0.0
        /// The anchor took the gesture's end: its momentum goes nowhere.
        private static var lifted = false
        /// That end, for its scroll view once the slide arrives (`finish`) or the next gesture begins: a scroll view
        /// that never sees its gesture end reports no scroll phase again (a probe app).
        private static var end: (event: NSEvent, scrollView: NSScrollView)?

        /// The taken gesture's end to its scroll view, at its page now, stamped now: as fingers that stopped, so the
        /// system's snap has nothing left to do. With the lift's time, it flung on 4 pt past the page and came back.
        static func finish() {
            guard let end else { return }
            self.end = nil
            let now = end.event.cgEvent?.copy()
            now?.timestamp = CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            end.scrollView.scrollWheel(with: now.flatMap(NSEvent.init(cgEvent:)) ?? end.event)
        }

        /// Whether the event went to a scroll view or turned the strip.
        private static func route(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if event.phase.isEmpty, event.momentumPhase.isEmpty {
                return wheel(event, sideways: abs(deltaX) > abs(deltaY) ? deltaX : 0)
            }
            if event.phase == .began {
                finish()
                picked = false
                target = nil
                moved = 0
                speed = 0
                lifted = false
            }
            // A scroll moves the content against the fingers' delta; half the last speed smooths a jittery step.
            if event.phase == .changed, event.timestamp > last {
                speed = speed / 2 - deltaX / (event.timestamp - last) / 2
            }
            // Fingers that stopped before they lifted.
            if event.phase == .ended, event.timestamp - last > 0.05 {
                speed = 0
            }
            last = event.timestamp
            if event.phase == .ended, let target, let lift = anchor(target)?.lift {
                end = (event, target)
                lifted = lift(speed)
                if lifted {
                    return true
                }
                end = nil
            }
            if lifted, !event.momentumPhase.isEmpty {
                return true
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
            if !event.hasPreciseScrollingDeltas, let step = anchor(scrollView)?.step {
                if Date.now.timeIntervalSince(wheeled) > 0.3 {
                    step(deltaX > 0 ? -1 : 1)
                }
                wheeled = .now
            } else {
                scrollView.scrollWheel(with: event)
            }
            return true
        }

        private static func anchor(_ scrollView: NSScrollView?) -> ScrollAnchor.Anchor? {
            scrollView.flatMap { view in anchors.allObjects.first { $0.enclosingScrollView === view } }
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

    /// Marks a scroll view for the router: the strip with its page turn for wheels, the sidebar's pages with what a
    /// swipe's lift does, given the fingers' speed.
    struct ScrollAnchor: NSViewRepresentable {
        var step: ((Int) -> Void)?
        var lift: ((Double) -> Bool)?

        func makeNSView(context _: Context) -> Anchor {
            Anchor(step: step, lift: lift)
        }

        func updateNSView(_ view: Anchor, context _: Context) {
            view.step = step
            view.lift = lift
        }

        /// No size: over the sidebar's rows, a view the size of the pages took accessibility's hit tests, and XCUITest
        /// found no hit point for a row.
        func sizeThatFits(_: ProposedViewSize, nsView _: Anchor, context _: Context) -> CGSize? {
            .zero
        }

        final class Anchor: NSView {
            var step: ((Int) -> Void)?
            var lift: ((Double) -> Bool)?

            init(step: ((Int) -> Void)?, lift: ((Double) -> Bool)?) {
                self.step = step
                self.lift = lift
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if window != nil {
                    SwipeRouter.anchors.add(self)
                }
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    }
#endif
