import AppKit
import SwiftUI

/// The app's one scroll monitor (design D35). A gesture picks its axis once it moved 4 pt: a sideways one over the
/// sidebar's pages goes to them; any other goes to the view under the pointer as usual. The pages take its moves and
/// lift, not its momentum. A wheel picks per event; Shift makes it sideways. ⌥ + swipe: see docs/ui/swiping.mdx.
@MainActor
enum SwipeRouter {
    /// Once, at launch.
    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { route(event) } ? nil : event
        }
    }

    /// `row`: the sidebar's next (1) or previous (-1) workspace, or agent in the Agents view.
    private enum Step {
        case session(Int), row(Int)
    }

    /// The event's window shows its next (1) or previous (-1) session, as ⌥⌘[ ]; or the sidebar's row: the
    /// Agents view's agent, else the workspace (⌃⌘[ ]). Not under a panel, as the sidebar's pages.
    private static func take(_ step: Step, _ event: NSEvent) {
        guard let pages = WindowPages.windows.first(where: { $0.window === event.window }), !pages.panelOpen
        else { return }
        switch step {
        case let .session(offset): pages.step(offset)
        case let .row(offset):
            let sidebar = anchors.allObjects.first { $0.window === event.window && $0.marks.agent != nil }
            if let agent = sidebar?.marks.agent {
                agent(offset)
            } else {
                pages.current?.stepWorkspace(offset)
            }
        }
    }

    /// Every window's sidebar pages; each registers itself.
    fileprivate static let anchors = NSHashTable<PagesAnchor.Anchor>.weakObjects()
    /// The pages the current sideways gesture goes to, and whether it lifted; nil while it goes the usual way.
    private weak static var pager: PagesAnchor.Anchor?
    private static var lifted = false
    private static var picked = false
    /// ⌥ was held as the current gesture began.
    private static var option = false
    private static var moved = 0.0, sideways = 0.0
    private static var wheeled = Date.distantPast
    /// The gesture's sideways speed in the content's points a second, from its last moves.
    private static var speed = 0.0, last = 0.0

    /// Whether the event went to the sidebar's pages or stepped (⌥), not to the view under the pointer.
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
        return pager != nil || option
    }

    /// Where the gesture goes, by its axis: see `SwipeRouter`.
    private static func pick(_ event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            // With ⌥, the window's sidebar pages wherever the pointer is; with no sidebar (hidden, the overview's,
            // a floating pane's window), one session step.
            pager = anchors.allObjects.first { anchor in
                anchor.contains(event) || option && anchor.marks.drag != nil && anchor.marks.area.width > 0
                    && anchor.window === event.window
            }
            if pager == nil, option {
                take(.session(sideways > 0 ? 1 : -1), event)
            }
            pager?.marks.drag?(sideways, true)
        } else if option {
            take(.row(up(event) > 0 ? -1 : 1), event)
        }
    }

    /// The vertical delta toward the top of the pad (or a wheel turned away), whatever the scroll direction: up goes
    /// to the row above.
    private static func up(_ event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
    }

    private static func give(_ event: NSEvent, to pager: PagesAnchor.Anchor) {
        if event.phase == .changed {
            pager.marks.drag?(-event.scrollingDeltaX, false)
        } else if event.phase == .ended || event.phase == .cancelled, !lifted {
            lifted = true
            // A gesture the system took (Mission Control) turns no page.
            pager.marks.lift?(event.phase == .cancelled ? 0 : speed)
        }
    }

    /// A sideways wheel burst over the sidebar's pages turns one page; else it goes to the view under the pointer.
    /// With ⌥, a burst steps the session or the sidebar's row.
    private static func wheel(_ event: NSEvent) -> Bool {
        let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
        if event.modifierFlags.contains(.option) {
            let across = abs(deltaX) > abs(deltaY)
            turn({ take(across ? .session($0) : .row($0), event) }, across ? deltaX : up(event))
            return true
        }
        guard abs(deltaX) > abs(deltaY),
              let pages = anchors.allObjects.first(where: { $0.contains(event) }) else { return false }
        turn(pages.marks.step, deltaX)
        return true
    }

    /// One step per burst of wheel clicks (0.3 s apart at most); a zero delta (the other axis) none.
    private static func turn(_ step: ((Int) -> Void)?, _ delta: CGFloat) {
        if delta != 0, Date.now.timeIntervalSince(wheeled) > 0.3 {
            step?(delta > 0 ? -1 : 1)
        }
        wheeled = .now
    }
}

/// Marks the sidebar's pages for the router: they take a sideways swipe's moves (`drag`, the first one of a gesture
/// marked) and lift (with the fingers' speed), and a wheel's turn (`step`), within `area` (in the window, from its
/// top left) and down to the window's bottom (the dots and the filter too).
struct PagesAnchor: NSViewRepresentable {
    var step: ((Int) -> Void)?
    var drag: ((Double, Bool) -> Void)?
    var lift: ((Double) -> Void)?
    /// The Agents view's step for a ⌥ + swipe up or down, while it shows.
    var agent: ((Int) -> Void)?
    var area = CGRect.zero

    func makeNSView(context _: Context) -> Anchor {
        let view = Anchor()
        view.marks = self
        return view
    }

    func updateNSView(_ view: Anchor, context _: Context) {
        view.marks = self
    }

    /// No size: over the sidebar's rows, a view the size of the pages took accessibility's hit tests, and XCUITest
    /// found no hit point for a row.
    func sizeThatFits(_: ProposedViewSize, nsView _: Anchor, context _: Context) -> CGSize? {
        .zero
    }

    final class Anchor: NSView {
        var marks = PagesAnchor()

        /// Under the event, for the sidebar's pages. The window's content view is its whole SwiftUI host, the
        /// window's full size; its points count from the bottom.
        func contains(_ event: NSEvent) -> Bool {
            guard marks.drag != nil, let window, event.window === window,
                  let height = window.contentView?.bounds.height else { return false }
            let point = event.locationInWindow
            let area = marks.area
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

extension Animation {
    /// The sidebar's session pages: 0.2 s with no bounce (0.14 s felt too
    /// quick and odd). A swipe's slide starts at the fingers' `speed`
    /// toward the page `distance` away (in pages a second, and pages), so it goes on from the lift.
    static func session(speed: Double = 0, distance: Double = 0) -> Animation {
        // Critically damped, it would go past the page from a relative speed over ω = 2π / response.
        let response = 0.2, initial = distance == 0 ? 0 : min(max(speed / distance, 0), 2 * .pi / response)
        return Animation(Arrive(spring: .interpolatingSpring(duration: response, bounce: 0, initialVelocity: initial)))
    }
}

/// A spring that is logically complete once within half a point of its end. Its own logical end, at its 0.2 s, left a
/// slow lift's pages up to 3 pt short: the session's show (100 ms of main thread) held them there, then they jumped.
private struct Arrive: CustomAnimation {
    let spring: Animation

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let now = spring.animate(value: value, time: time, context: &context)
        var left = value
        left -= now ?? value
        context.isLogicallyComplete = left.magnitudeSquared < 0.25
        return now
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        spring.velocity(value: value, time: time, context: context)
    }

    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                          context: inout AnimationContext<V>) -> Bool
    {
        spring.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }
}
