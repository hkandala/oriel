// The three-finger swipe's checks (`make test`), compiled with Oriel/Views/ThreeFingers.swift: no trackpad on CI,
// and a UI test cannot post touches.
import CoreGraphics

@main
enum ThreeFingersCheck {
    /// The steps of fingers at these offsets from where they landed, 10 ms apart.
    static func steps(_ moves: [(Double, Double)], fingers: Int = 3) -> [ThreeFingers.Step] {
        var recognizer = ThreeFingers()
        var steps: [ThreeFingers.Step] = []
        for (index, (sideways, upward)) in moves.enumerated() {
            let points = (0 ..< fingers).map { CGPoint(x: 100 + 20 * Double($0) + sideways, y: 100 + upward) }
            if let step = recognizer.feed(points, at: Double(index) * 0.01) {
                steps.append(step)
            }
        }
        return steps
    }

    static func main() {
        let left = (0 ... 10).map { (-3.0 * Double($0), 0.0) }
        precondition(steps(left) == [.session(1)], "fingers to the left: the next session, once")
        precondition(steps(left.map { (-$0.0, 0) }) == [.session(-1)], "to the right: the previous one")
        precondition(steps(left.map { (0, -$0.0) }) == [.workspace(1)], "up: the next workspace")
        precondition(steps(left.map { (0, $0.0) }) == [.workspace(-1)], "down: the previous one")
        precondition(steps(left, fingers: 2).isEmpty, "two fingers scroll")
        precondition(steps(left, fingers: 4).isEmpty, "four are the system's")
        precondition(steps(left.map { ($0.0, $0.0) }).isEmpty, "a diagonal steps nothing")
        precondition(steps(Array(left.prefix(4))).isEmpty, "a 9 pt move steps nothing")
        precondition(steps([(0, 0), (-30, 0)]).isEmpty, "nor one within 60 ms of the landing")

        var recognizer = ThreeFingers()
        let three = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 40, y: 0)]
        _ = recognizer.feed(three, at: 0)
        precondition(recognizer.feed(three.map { CGPoint(x: $0.x - 30, y: 0) }, at: 0.1, cancelled: true) == nil,
                     "a swipe the system took steps nothing")
        _ = recognizer.feed([], at: 0.2)
        _ = recognizer.feed(three, at: 0.3)
        precondition(recognizer.feed(three.map { CGPoint(x: $0.x - 30, y: 0) }, at: 0.4) == .session(1),
                     "after the lift, the next swipe steps")
        print("three-fingers-check: ok")
    }
}
