import SwiftUI

/// Rex's three working dots: each fades 0.3 → 0.85 → 0.3 over 1.2 s, 0.2 s after the one before, from the wall
/// clock so every tab is in step. Core Animation runs them, at most 15 frames a second, so the app does no work per
/// frame (a TimelineView per dots made SwiftUI lay out the window at every tick). Still under Reduce
/// Motion (but with `-forceMotion`) and on a sidebar page off to the side.
struct WorkingDots: NSViewRepresentable {
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreen) private var offscreen

    /// One dot, repeated 5.5 pt and 0.2 s apart: as an HStack of 3.5 pt squares 2 pt apart, centered in 14 pt.
    func makeNSView(context _: Context) -> NSView {
        let view = Dots(), dots = CAReplicatorLayer(), dot = CALayer()
        view.wantsLayer = true
        dot.frame = CGRect(x: -0.25, y: 5.25, width: 3.5, height: 3.5)
        dot.cornerRadius = 1.75
        dot.opacity = 0.6
        dots.instanceCount = 3
        dots.instanceTransform = CATransform3DMakeTranslation(5.5, 0, 0)
        dots.instanceDelay = 0.2
        dots.addSublayer(dot)
        view.layer?.addSublayer(dots)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let dot = view.layer?.sublayers?.first?.sublayers?.first else { return }
        dot.backgroundColor = look.working.resolve(in: context.environment).cgColor
        if reduceMotion && !Animation.forceMotion || offscreen {
            dot.removeAllAnimations()
        } else if dot.animation(forKey: "working") == nil {
            dot.add(Self.fade(in: dot), forKey: "working")
        }
    }

    func sizeThatFits(_: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
        CGSize(width: 14, height: 14)
    }

    /// Clicks go through to the row's button.
    final class Dots: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }

    /// Key times 0, 0.25 and 0.5 of the cycle, eased in and out; rests at 0.3 for the second half. Its phase is
    /// the wall clock's.
    private static func fade(in layer: CALayer) -> CAAnimation {
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.3, 0.85, 0.3, 0.3]
        fade.keyTimes = [0, 0.25, 0.5, 1]
        fade.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut), .init(name: .linear)]
        fade.duration = 1.2
        fade.repeatCount = .infinity
        fade.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 15)
        let phase = Date.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2)
        fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - phase
        return fade
    }
}

extension EnvironmentValues {
    /// A sidebar page off to the side: its dots stand still.
    @Entry var offscreen = false
}

/// Working's state symbol, as macOS's spinner: eight ticks, brightest in front, that step a tick clockwise every 0.1 s,
/// from the wall clock so every spinner is in step. Core Animation runs it, a frame per step: SF Symbols' own
/// `symbolEffect` took about 6 % of a core per spinner. Still under Reduce Motion (but with `-forceMotion`) and on a
/// sidebar page off to the side.
struct Spinner: NSViewRepresentable {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreen) private var offscreen

    func makeNSView(context _: Context) -> NSView {
        let view = WorkingDots.Dots(), ticks = CAReplicatorLayer(), tick = CALayer()
        view.wantsLayer = true
        ticks.frame = CGRect(x: 0, y: 0, width: 12, height: 12)
        tick.frame = CGRect(x: 5.25, y: 9, width: 1.5, height: 3)
        tick.cornerRadius = 0.75
        ticks.instanceCount = 8
        // Each tick a step counterclockwise and dimmer: the trail behind the front one.
        ticks.instanceTransform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
        ticks.instanceAlphaOffset = -0.1
        ticks.addSublayer(tick)
        view.layer?.addSublayer(ticks)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let ticks = view.layer?.sublayers?.first, let tick = ticks.sublayers?.first else { return }
        tick.backgroundColor = color.resolve(in: context.environment).cgColor
        if reduceMotion && !Animation.forceMotion || offscreen {
            ticks.removeAllAnimations()
        } else if ticks.animation(forKey: "spin") == nil {
            let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            spin.values = (0 ..< 8).map { -Double($0) * .pi / 4 }
            spin.calculationMode = .discrete
            spin.duration = 0.8
            spin.repeatCount = .infinity
            // A frame per step and no more.
            spin.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 10)
            let phase = Date.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8)
            spin.beginTime = ticks.convertTime(CACurrentMediaTime(), from: nil) - phase
            ticks.add(spin, forKey: "spin")
        }
    }

    func sizeThatFits(_: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
        CGSize(width: 12, height: 12)
    }
}
