#if os(macOS)
    import AppKit
    import SwiftUI

    /// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one goes to
    /// the sidebar's pages when over them, else to the pages of the scroll view under the pointer (the strip's, over a
    /// card), or that scroll view, so a terminal never sees it; any other goes to the view under the pointer as usual.
    /// Pages take its moves and lift, not its momentum. A wheel picks per event; Shift makes it sideways. Three-finger
    /// swipes: see docs/ui/swiping.mdx.
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

        /// The event's window shows its next (1) or previous (-1) session, as ⌥⌘[ ]; or the sidebar's row: the
        /// Agents view's agent, else the workspace (⌃⌘[ ]). Not under a panel, as the sidebar's pages.
        private static func take(_ step: ThreeFingers.Step, _ event: NSEvent) {
            guard let pages = WindowPages.windows.first(where: { $0.window === event.window }), !pages.panelOpen
            else { return }
            switch step {
            case let .session(offset): pages.step(offset)
            case let .row(offset):
                let sidebar = anchors.allObjects.first { $0.window === event.window && $0.agent != nil }
                if let agent = sidebar?.agent {
                    agent(offset)
                } else {
                    pages.current?.stepWorkspace(offset)
                }
            }
        }

        /// Every window's strip, overview and sidebar pages; each registers itself.
        fileprivate static let anchors = NSHashTable<ScrollAnchor.Anchor>.weakObjects()
        /// Where the current sideways gesture goes; nil while it goes the usual way.
        private weak static var target: NSScrollView?
        /// The pages the current sideways gesture goes to, and whether it lifted.
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
                return wheel(event)
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
            return target != nil || pager != nil
        }

        /// Where the gesture goes, by its axis: see `SwipeRouter`.
        private static func pick(_ event: NSEvent) {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                pager = anchors.allObjects.first { $0.contains(event) }
                if pager == nil {
                    target = scrollView(event)
                    // The strip's and the overview's pages take it as the sidebar's do (phase 31).
                    if let paged = anchor(target), paged.drag != nil {
                        (pager, target) = (paged, nil)
                    }
                }
                pager?.drag?(sideways, true)
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

        /// A sideways wheel step: over the sidebar's pages, or over the strip's or the overview's as a burst (they have
        /// no paging of their own; a mouse's line steps would only nudge them), it turns one page; else it goes to the
        /// scroll view under the pointer.
        private static func wheel(_ event: NSEvent) -> Bool {
            let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            guard abs(deltaX) > abs(deltaY) else { return false }
            if let pages = anchors.allObjects.first(where: { $0.contains(event) }) {
                turn(pages.step, deltaX)
                return true
            }
            guard let scrollView = scrollView(event) else { return false }
            if let step = anchor(scrollView)?.step {
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

    /// Marks a scroll view for the router: the strip with its page turn for wheels. With `drag`, its pages take a
    /// sideways swipe's moves (the first one of a gesture marked) and lift (with the fingers' speed), not the scroll
    /// view (`Paging`). With an `area` too, it marks the sidebar's pages, which take a swipe and a wheel's turn within
    /// it (in the window, from its top left) and down to the window's bottom (the dots and the filter too).
    struct ScrollAnchor: NSViewRepresentable {
        var step: ((Int) -> Void)?
        var drag: ((Double, Bool) -> Void)?
        var lift: ((Double) -> Void)?
        /// The Agents view's step for a three-finger swipe up or down, while it shows.
        var agent: ((Int) -> Void)?
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
            view.agent = agent
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
            var agent: ((Int) -> Void)?
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

    /// A paged scroll view's pages that a swipe moves as the sidebar's (the strip's, the overview's; phase 31): they
    /// follow the fingers one to one and slide on from the lift (`slide`). With the system's paging a 140 pt flick at
    /// 625 pt/s slid back to its page over 0.55 s (CI).
    @MainActor
    final class Paging {
        /// The offset and the page width as last laid out (`laid`), or moved to.
        private var offset = 0.0, width = 1.0
        /// The slide's end offset, and what runs once the pages are within a point of it.
        private var landing: (offset: Double, land: () -> Void)?

        /// From `onScrollGeometryChange`, at each frame of a slide.
        func laid(_ geometry: ScrollGeometry) {
            (offset, width) = (geometry.contentOffset.x, max(geometry.containerSize.width, 1))
            Latency.shared.slid(offset, "page")
            if let landing, abs(offset - landing.offset) < 1 {
                self.landing = nil
                Latency.shared.shown()
                landing.land()
            }
        }

        /// The router's moves, in points toward later pages, within the first and last of `count` pages.
        func drag(_ delta: Double, count: Int, _ position: Binding<ScrollPosition>) {
            landing = nil
            offset = min(max(offset + delta, 0), Double(max(count - 1, 0)) * width)
            withTransaction(\.animation, nil) { position.wrappedValue.scrollTo(x: offset) }
        }

        /// The router's lift: the pages slide to the page it lands on (at once under Reduce Motion), and `land` runs
        /// with its id as they arrive, unless a key, a click or another swipe moved them meanwhile. Not at the
        /// animation's `.logicallyComplete`: for a scroll that fires at once, and the tab's terminals or the session
        /// shown in the slide's first frame held it for 50–150 ms (CI), so it jumped most of a page (phase 31).
        func lift(_ speed: Double, ids: [String], _ position: Binding<ScrollPosition>, reduceMotion: Bool,
                  land: @escaping (String) -> Void)
        {
            let page = offset / width, index = Swipe.landing(page, speed: speed, count: ids.count)
            guard ids.indices.contains(index) else { return }
            let id = ids[index]
            Latency.shared.lifted(offset, "page")
            // On the page already (a drag clamped at the last one): no animation, which might never end.
            if reduceMotion && !Animation.forceMotion || abs(Double(index) - page) < 0.001 {
                position.wrappedValue.scrollTo(id: id, anchor: .leading)
                return land(id)
            }
            landing = (Double(index) * width, {
                if position.wrappedValue.viewID(type: String.self) == id {
                    land(id)
                }
            })
            withAnimation(Self.slide(speed, (Double(index) - page) * width)) {
                position.wrappedValue.scrollTo(id: id, anchor: .leading)
            }
        }

        /// From the fingers' `speed` over the `distance` left (points a second, points), in at most 0.28 s: it starts
        /// at their speed (a cubic whose x is linear, so its first slope is the start's speed in distances per
        /// duration), speeds up only as much as that time needs and eases out; when their speed alone covers it in
        /// that time it only slows down (slope 2: a quadratic ease-out). The session spring (0.2 s) went from 1.6k
        /// to 15k pt/s in two frames after a slow lift, a page in four (capture F, phase 31): it looked cut.
        private static func slide(_ speed: Double, _ distance: Double) -> Animation {
            let toward = max(distance < 0 ? -speed : speed, 0), length = max(abs(distance), 1)
            let duration = min(0.28, 2 * length / toward)
            return .timingCurve(1 / 3, toward * duration / length / 3, 2 / 3, 1, duration: duration)
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

        /// The page of `count` that a lift at `page` (from the first) lands on, from the fingers' `speed` in points a
        /// second: the next one that way, or the nearest when slow.
        static func landing(_ page: Double, speed: Double, count: Int) -> Int {
            let near = abs(speed) < 100 ? page.rounded() : speed > 0 ? page.rounded(.up) : page.rounded(.down)
            return min(max(Int(near), 0), count - 1)
        }
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
