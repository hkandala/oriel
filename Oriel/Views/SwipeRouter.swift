#if os(macOS)
    import AppKit
    import SwiftUI

    /// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one goes to
    /// the sidebar's pages when over them, else to the scroll view under the pointer (the strip, over a card), so a
    /// terminal never sees it; any other goes to the view under the pointer as usual. Its momentum follows. A wheel
    /// picks per event; Shift makes it sideways.
    @MainActor
    enum SwipeRouter {
        /// Once, at launch.
        static func install() {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated { route(event) } ? nil : event
            }
        }

        /// Every window's strip (for wheel clicks) and sidebar pages; each registers itself.
        fileprivate static let anchors = NSHashTable<ScrollAnchor.Anchor>.weakObjects()
        /// Where the current sideways gesture goes; nil while it goes the usual way.
        private weak static var target: NSScrollView?
        /// The sidebar's pages, when the current sideways gesture goes to them, and whether it lifted.
        private weak static var pager: ScrollAnchor.Anchor?
        private static var lifted = false
        private static var picked = false
        private static var moved = 0.0, sideways = 0.0
        private static var wheeled = Date.distantPast
        /// The gesture's sideways speed in the content's points a second, from its last moves.
        private static var speed = 0.0, last = 0.0

        /// Whether the event went to a scroll view, the sidebar's pages or turned the strip.
        private static func route(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if event.phase.isEmpty, event.momentumPhase.isEmpty {
                return wheel(event, sideways: abs(deltaX) > abs(deltaY) ? deltaX : 0)
            }
            if event.phase == .began {
                picked = false
                target = nil
                pager = nil
                lifted = false
                moved = 0
                sideways = 0
                speed = 0
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
            // The pages take the moves and the lift; the momentum goes nowhere.
            if let pager {
                if event.phase == .changed {
                    pager.drag?(-deltaX)
                } else if event.phase == .ended || event.phase == .cancelled, !lifted {
                    lifted = true
                    pager.lift?(speed)
                }
                return true
            }
            if !picked {
                moved += abs(deltaX) + abs(deltaY)
                sideways -= deltaX
                if moved >= 4 {
                    picked = true
                    if abs(deltaX) > abs(deltaY) {
                        pager = anchors.allObjects.first { $0.contains(event) }
                        pager?.drag?(sideways)
                        target = pager == nil ? scrollView(event) : nil
                    }
                }
            }
            target?.scrollWheel(with: event)
            return target != nil || pager != nil
        }

        /// A sideways wheel step: over the sidebar's pages, or over the strip as a burst of line steps (a mouse, which
        /// would only nudge a paged strip), it turns one page; else it goes to the scroll view under the pointer.
        private static func wheel(_ event: NSEvent, sideways deltaX: CGFloat) -> Bool {
            guard deltaX != 0 else { return false }
            if let pages = anchors.allObjects.first(where: { $0.contains(event) }) {
                turn(pages.step, deltaX)
                return true
            }
            guard let scrollView = scrollView(event) else { return false }
            if !event.hasPreciseScrollingDeltas, let step = anchor(scrollView)?.step {
                turn(step, deltaX)
            } else {
                scrollView.scrollWheel(with: event)
            }
            return true
        }

        private static func turn(_ step: ((Int) -> Void)?, _ deltaX: CGFloat) {
            if Date.now.timeIntervalSince(wheeled) > 0.3 {
                step?(deltaX > 0 ? -1 : 1)
            }
            wheeled = .now
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

    /// Marks a scroll view for the router: the strip with its page turn for wheels. With `drag`, it marks the sidebar's
    /// pages instead, which take a sideways swipe's moves and lift (with the fingers' speed) and a wheel's turn: from
    /// its place, at their top leading corner, `width` wide and down to the window's bottom (the dots and the filter
    /// too).
    struct ScrollAnchor: NSViewRepresentable {
        var step: ((Int) -> Void)?
        var drag: ((Double) -> Void)?
        var lift: ((Double) -> Void)?
        var width = 0.0

        func makeNSView(context: Context) -> Anchor {
            let view = Anchor()
            updateNSView(view, context: context)
            return view
        }

        func updateNSView(_ view: Anchor, context _: Context) {
            view.step = step
            view.drag = drag
            view.lift = lift
            view.width = width
        }

        /// No size: over the sidebar's rows, a view the size of the pages took accessibility's hit tests, and XCUITest
        /// found no hit point for a row.
        func sizeThatFits(_: ProposedViewSize, nsView _: Anchor, context _: Context) -> CGSize? {
            .zero
        }

        final class Anchor: NSView {
            var step: ((Int) -> Void)?
            var drag: ((Double) -> Void)?
            var lift: ((Double) -> Void)?
            var width = 0.0

            /// Under the event, for the sidebar's pages.
            func contains(_ event: NSEvent) -> Bool {
                guard drag != nil, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
                let corner = convert(NSPoint.zero, to: nil), point = event.locationInWindow
                return point.x >= corner.x && point.x < corner.x + width && point.y <= corner.y
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
