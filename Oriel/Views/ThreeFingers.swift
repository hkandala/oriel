#if os(macOS)
    import CoreGraphics
    import Foundation

    /// A three-finger swipe from the trackpad's touches (`SwipeRouter`): three fingers down 60 ms (a fourth one
    /// landing late is a system swipe) that moved 20 pt mostly one way. One step, then nothing until the fingers lift.
    struct ThreeFingers {
        enum Step: Equatable {
            case session(Int), workspace(Int)
        }

        /// Where and when the three fingers were first down together.
        private var start: (center: CGPoint, time: TimeInterval)?
        private var done = false

        /// `points`: the fingers on the pad, in its points (y up); `cancelled`: the system took the touches.
        mutating func feed(_ points: [CGPoint], at time: TimeInterval, cancelled: Bool = false) -> Step? {
            if points.isEmpty {
                self = Self()
                return nil
            }
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
            // As the system's swipes: fingers to the left show the next session, up the next workspace.
            return abs(deltaX) > abs(deltaY) ? .session(deltaX < 0 ? 1 : -1) : .workspace(deltaY > 0 ? 1 : -1)
        }
    }
#endif
