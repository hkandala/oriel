// A two-finger trackpad swipe at a known speed, for the session swipe test (phase 27): the pointer to x y (screen
// points, top left), then a scroll that begins, moves `step` pt sideways `steps` times 16 ms apart, and ends with no
// momentum. Posted to the HID system: the sandboxed UI test runner cannot post events, and the app takes scrolls
// posted to its pid without scrolling.
// Usage: swift scripts/swipe.swift <x> <y> <step> <steps>
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst().prefix(4).compactMap { Double($0) }
guard args.count == 4 else { fatalError("usage: swipe.swift <x> <y> <step> <steps>") }
let point = CGPoint(x: args[0], y: args[1]), steps = Int(args[3])
CGWarpMouseCursorPosition(point)
Thread.sleep(forTimeInterval: 0.3)
for index in 0 ... steps + 1 {
    // kCGScrollPhaseBegan, Changed, Ended.
    let phase: Int64 = index == 0 ? 1 : index > steps ? 4 : 2
    let delta = index == 0 || index > steps ? 0 : Int32(args[2])
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: delta,
                              wheel3: 0) else { continue }
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.location = point
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.016)
}

// Momentum, as a trackpad sends after the lift: deltas that decay for about 0.6 s.
if CommandLine.arguments.count > 5 {
    var delta = args[2]
    for index in 0 ... 40 {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0,
                                  wheel2: Int32(delta.rounded()), wheel3: 0) else { continue }
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: index == 0 ? 1 : index == 40 ? 3 : 2)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.location = point
        event.post(tap: .cghidEventTap)
        delta *= 0.9
        Thread.sleep(forTimeInterval: 0.016)
    }
}
