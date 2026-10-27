// A mouse drag through several points, for the drag tests that need two legs (a tab held over the
// workspace button opens its menu, then drops on a row there): XCUITest drags to one point only. Presses at x y (screen
// points, top left) for 0.3 s, then moves to each next point over 0.3 s and holds there for its seconds, then lets go.
// Posted to the HID system, as scripts/swipe.swift does. Only from an Oriel window: never into another app.
// Usage: swift scripts/drag.swift <x> <y> (<x> <y> <hold>)...
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count >= 5, (args.count - 2) % 3 == 0 else { fatalError("usage: drag.swift <x> <y> (<x> <y> <hold>)...") }
let start = CGPoint(x: args[0], y: args[1])
let points = [start] + stride(from: 2, to: args.count, by: 3).map { CGPoint(x: args[$0], y: args[$0 + 1]) }
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let front = windows.first { window in
    let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    return window[kCGWindowLayer as String] as? Int == 0 && bounds?.contains(start) == true
}

let frame = (front?[kCGWindowBounds as String] as? NSDictionary)
    .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .null

guard front?[kCGWindowOwnerName as String] as? String == "Oriel", points.allSatisfy({ frame.contains($0) })
else { fatalError("not all of \(points) in the Oriel window at \(start)") }

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

CGWarpMouseCursorPosition(start)
Thread.sleep(forTimeInterval: 0.3)
post(.leftMouseDown, start)
Thread.sleep(forTimeInterval: 0.3)
var point = start
for index in stride(from: 2, to: args.count, by: 3) {
    let next = CGPoint(x: args[index], y: args[index + 1])
    for step in 1 ... 20 {
        let part = Double(step) / 20
        post(.leftMouseDragged, CGPoint(x: point.x + (next.x - point.x) * part, y: point.y + (next.y - point.y) * part))
        Thread.sleep(forTimeInterval: 0.015)
    }
    point = next
    Thread.sleep(forTimeInterval: args[index + 2])
}

post(.leftMouseUp, point)
