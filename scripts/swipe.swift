// A two-finger trackpad swipe at a known speed, for the session swipe test (phase 27): the pointer to x y (screen
// points, top left), then a scroll that begins, moves `step` pt sideways `steps` times 16 ms apart and ends, then
// momentum that decays for about 0.6 s, as a trackpad sends; with `pause` ms, the fingers stop that long before they
// lift, with no momentum. Posted to the HID system: the sandboxed UI test runner cannot post events, and the app takes
// scrolls posted to its pid without scrolling. Only over an Oriel window: never into another app (a herdr client).
// With `vertical` 1, the scroll goes up or down instead (phase 29), for the stress test's frame meter.
// Usage: swift scripts/swipe.swift <x> <y> <step> <steps> [pause [vertical]]
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count >= 4 else { fatalError("usage: swipe.swift <x> <y> <step> <steps> [pause [vertical]]") }
let point = CGPoint(x: args[0], y: args[1]), steps = Int(args[3]), pause = args.count > 4 ? args[4] / 1000 : 0
let vertical = args.count > 5 && args[5] == 1
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let front = windows.first { window in
    let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    return window[kCGWindowLayer as String] as? Int == 0 && bounds?.contains(point) == true
}

guard front?[kCGWindowOwnerName as String] as? String == "Oriel" else { fatalError("no Oriel window at \(point)") }

func post(_ delta: Double, _ field: CGEventField, _ phase: Int64) {
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: vertical ? Int32(delta.rounded()) : 0,
                              wheel2: vertical ? 0 : Int32(delta.rounded()), wheel3: 0) else { return }
    event.setIntegerValueField(field, value: phase)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.location = point
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.016)
}

CGWarpMouseCursorPosition(point)
Thread.sleep(forTimeInterval: 0.3)
// kCGScrollPhaseBegan, Changed, Ended; then kCGMomentumScrollPhaseBegin, Continue, End.
post(0, .scrollWheelEventScrollPhase, 1)
for _ in 0 ..< steps {
    post(args[2], .scrollWheelEventScrollPhase, 2)
}

Thread.sleep(forTimeInterval: pause)
post(0, .scrollWheelEventScrollPhase, 4)
for index in 0 ..< (pause > 0 ? 0 : 41) {
    post(args[2] * pow(0.9, Double(index)), .scrollWheelEventMomentumPhase, index == 0 ? 1 : index == 40 ? 3 : 2)
}
