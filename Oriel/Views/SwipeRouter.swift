#if os(macOS)
    import AppKit
    import SwiftUI

    /// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one goes to
    /// the sidebar's pages when over them, else to the scroll view under the pointer (the strip, over a card), so a
    /// terminal never sees it; any other goes to the view under the pointer as usual. Its momentum follows, except to
    /// the sidebar's pages. A wheel picks per event; Shift makes it sideways. ⌥ + swipe and three-finger swipes: see
    /// docs/ui/swiping.mdx.
    @MainActor
    enum SwipeRouter {
        /// Once, at launch.
        static func install() {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated { route(event) } ? nil : event
            }
            // The trackpad's touches, which a window gets once a view in it takes them (`WindowReader`).
            NSEvent.addLocalMonitorForEvents(matching: .gesture) { event in
                MainActor.assumeIsolated { touched(event) }
                return event
            }
        }

        private static var fingers = ThreeFingers()

        private static func touched(_ event: NSEvent) {
            let touches = event.allTouches()
            let down = touches.filter { !$0.isResting && !$0.phase.isDisjoint(with: .touching) }
            // A lift, or new touches (after a lift the app missed).
            if down.allSatisfy({ $0.phase == .began }) {
                fingers = ThreeFingers()
            }
            let points = down.map { touch in
                CGPoint(x: touch.normalizedPosition.x * touch.deviceSize.width,
                        y: touch.normalizedPosition.y * touch.deviceSize.height)
            }
            if let step = fingers.feed(points, at: event.timestamp,
                                       cancelled: touches.contains { $0.phase == .cancelled })
            {
                take(step, event)
            }
        }

        /// The event's window shows its next (1) or previous (-1) session or workspace, as ⌥⌘[ ] and ⌃⌘[ ]; not under
        /// a panel, as the sidebar's pages.
        private static func take(_ step: ThreeFingers.Step, _ event: NSEvent) {
            guard let pages = WindowPages.windows.first(where: { $0.window === event.window }), !pages.panelOpen
            else { return }
            switch step {
            case let .session(offset): pages.step(offset)
            case let .workspace(offset): pages.current?.stepWorkspace(offset)
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
        /// ⌥ was held as the current gesture began.
        private static var option = false
        private static var moved = 0.0, sideways = 0.0
        private static var wheeled = Date.distantPast
        /// The gesture's sideways speed in the content's points a second, from its last moves.
        private static var speed = 0.0, last = 0.0

        /// Whether the event went to a scroll view, the sidebar's pages or turned the strip.
        private static func route(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if event.phase.isEmpty, event.momentumPhase.isEmpty {
                return wheel(event)
            }
            if event.phase == .mayBegin || event.phase == .began {
                option = event.modifierFlags.contains(.option)
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
            // The next touch, which may end with no move (`.cancelled`): not the last swipe's.
            if event.phase == .mayBegin {
                pager = nil
            }
            // A scroll moves the content against the fingers' delta; half the last speed smooths a jittery step.
            if event.phase == .changed, event.timestamp > last {
                speed = speed / 2 - deltaX / (event.timestamp - last) / 2
            }
            // Fingers that stopped before they lifted. Not 50 ms: CI's VM posts a quick flick's moves about 50 ms
            // apart.
            if event.phase == .ended, event.timestamp - last > 0.1 {
                speed = 0
            }
            last = event.timestamp
            // The pages take the moves and the lift; the momentum goes nowhere.
            if let pager {
                give(event, to: pager)
                return true
            }
            if !picked {
                moved += abs(deltaX) + abs(deltaY)
                sideways -= deltaX
                if moved >= 4 {
                    picked = true
                    pick(event)
                }
            }
            target?.scrollWheel(with: event)
            return target != nil || pager != nil || option
        }

        /// Where the gesture goes, by its axis: see `SwipeRouter`.
        private static func pick(_ event: NSEvent) {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                pager = anchors.allObjects.first { anchor in
                    anchor.contains(event) || option && anchor.drag != nil && anchor.window === event.window
                }
                pager?.drag?(sideways, true)
                if pager == nil {
                    if option {
                        take(.session(sideways > 0 ? 1 : -1), event)
                    } else {
                        target = scrollView(event)
                    }
                }
            } else if option {
                take(.workspace(event.scrollingDeltaY > 0 ? -1 : 1), event)
            }
        }

        private static func give(_ event: NSEvent, to pager: ScrollAnchor.Anchor) {
            if event.phase == .changed {
                pager.drag?(-event.scrollingDeltaX, false)
            } else if event.phase == .ended || event.phase == .cancelled, !lifted {
                lifted = true
                // A gesture the system took (Mission Control) turns no page.
                pager.lift?(event.phase == .cancelled ? 0 : speed)
            }
        }

        /// A sideways wheel step: over the sidebar's pages, or over the strip as a burst of line steps (a mouse, which
        /// would only nudge a paged strip), it turns one page; else it goes to the scroll view under the pointer. With
        /// ⌥, a burst steps the session or the workspace.
        private static func wheel(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if event.modifierFlags.contains(.option) {
                let across = abs(deltaX) > abs(deltaY)
                turn({ take(across ? .session($0) : .workspace($0), event) }, across ? deltaX : deltaY)
                return true
            }
            guard abs(deltaX) > abs(deltaY) else { return false }
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

        /// One step per burst of wheel clicks (0.3 s apart at most); a zero delta (the other axis) none.
        private static func turn(_ step: ((Int) -> Void)?, _ delta: CGFloat) {
            if delta != 0, Date.now.timeIntervalSince(wheeled) > 0.3 {
                step?(delta > 0 ? -1 : 1)
            }
            wheeled = .now
        }

        private static func anchor(_ scrollView: NSScrollView?) -> ScrollAnchor.Anchor? {
            scrollView.flatMap { view in anchors.allObjects.first { $0.enclosingScrollView === view } }
        }

        /// The innermost scroll view under the pointer that can scroll sideways (its document is wider than its clip
        /// view): over a card, the strip. None can (a one-tab strip): the innermost still takes it, so a terminal never
        /// does.
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
    /// pages instead, which take a sideways swipe's moves (the first one of a gesture marked) and lift (with the
    /// fingers' speed) and a wheel's turn, within `area` (in the window, from its top left) and down to the window's
    /// bottom (the dots and the filter too).
    struct ScrollAnchor: NSViewRepresentable {
        var step: ((Int) -> Void)?
        var drag: ((Double, Bool) -> Void)?
        var lift: ((Double) -> Void)?
        var area = CGRect.zero

        func makeNSView(context: Context) -> Anchor {
            let view = Anchor()
            updateNSView(view, context: context)
            return view
        }

        func updateNSView(_ view: Anchor, context _: Context) {
            view.step = step
            view.drag = drag
            view.lift = lift
            view.area = area
        }

        /// No size: over the sidebar's rows, a view the size of the pages took accessibility's hit tests, and XCUITest
        /// found no hit point for a row.
        func sizeThatFits(_: ProposedViewSize, nsView _: Anchor, context _: Context) -> CGSize? {
            .zero
        }

        final class Anchor: NSView {
            var step: ((Int) -> Void)?
            var drag: ((Double, Bool) -> Void)?
            var lift: ((Double) -> Void)?
            var area = CGRect.zero

            /// Under the event, for the sidebar's pages. The window's content view is its whole SwiftUI host, the
            /// window's full size; its points count from the bottom.
            func contains(_ event: NSEvent) -> Bool {
                guard drag != nil, let window, event.window === window,
                      let height = window.contentView?.bounds.height else { return false }
                let point = event.locationInWindow
                return point.x >= area.minX && point.x < area.maxX && height - point.y >= area.minY
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

    /// Where the sidebar's session pages are: `slide` is observed only by `Pager`, so a swipe's moves redraw nothing
    /// else; `moving` by the sidebar, which lays out the other pages only then.
    @MainActor @Observable
    final class Swipe {
        /// In pages from the first: where the fingers hold them, else where they slide to or rest.
        var slide = 0.0
        /// In points, as last drawn: mid-slide, where a new swipe takes the pages from.
        @ObservationIgnored var drawn = 0.0
        /// The fingers hold the pages, or they slide.
        var moving = false
        /// Counts the moves, so only the latest one's end sets the pages at rest.
        @ObservationIgnored var moves = 0
    }

    /// The pages side by side, the one at `swipe.slide` in view.
    struct Pager<Content: View>: View {
        let swipe: Swipe
        let width: Double
        @ViewBuilder let content: Content

        var body: some View {
            // At rest it holds only the page in view.
            content.modifier(Slid(offset: swipe.moving ? swipe.slide * width : 0, swipe: swipe))
                .frame(width: width, alignment: .leading)
                .frame(maxHeight: .infinity)
                .clipped()
        }
    }

    /// The pages' offset, animatable, so a test can read it at each frame of a slide.
    private struct Slid: ViewModifier, Animatable {
        var offset: Double
        let swipe: Swipe
        var animatableData: Double {
            get { offset }
            set { offset = newValue }
        }

        func body(content: Content) -> some View {
            if swipe.moving {
                swipe.drawn = offset
                Latency.shared.slid(offset)
            }
            return content.offset(x: -offset)
        }
    }
#endif
