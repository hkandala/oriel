import CoreGraphics
import Foundation

/// A three-finger swipe from the trackpad's touches (`SwipeRouter`): three fingers down 60 ms (a fourth one
/// landing late is a system swipe) that moved 20 pt mostly one way. One step, then nothing until the fingers lift
/// or the touches pause 0.2 s.
struct ThreeFingers {
    enum Step: Equatable {
        /// `row`: the sidebar's next (1) or previous (-1) workspace, or agent in the Agents view.
        case session(Int), row(Int)
    }

    /// Where and when the three fingers were first down together.
    private var start: (center: CGPoint, time: TimeInterval)?
    private var done = false
    private var last = -TimeInterval.infinity

    /// `points`: the fingers on the pad, in its points (y up); `cancelled`: the system took the touches.
    mutating func feed(_ points: [CGPoint], at time: TimeInterval, cancelled: Bool = false) -> Step? {
        // The pad reports fingers on it every few milliseconds, still ones too: a pause means they lifted where
        // the app did not see it (another app's window), and AppKit may report the next touches as moved, not began.
        if points.isEmpty || time - last > 0.2 {
            self = Self()
        }
        last = time
        guard !points.isEmpty else { return nil }
        if cancelled || points.count > 3 {
            done = true
        }
        guard !done, points.count == 3 else {
            start = nil
            return nil
        }
        let center = CGPoint(x: points.map(\.x).reduce(0, +) / 3, y: points.map(\.y).reduce(0, +) / 3)
        guard let start else {
            start = (center, time)
            return nil
        }
        let deltaX = center.x - start.center.x, deltaY = center.y - start.center.y
        let long = max(abs(deltaX), abs(deltaY)), short = min(abs(deltaX), abs(deltaY))
        guard time - start.time >= 0.06, long >= 20, long >= 2 * short else { return nil }
        done = true
        // Fingers to the left show the next session, as the system's swipes; up the row above in the sidebar, down
        // the one below.
        return abs(deltaX) > abs(deltaY) ? .session(deltaX < 0 ? 1 : -1) : .row(deltaY > 0 ? -1 : 1)
    }
}
