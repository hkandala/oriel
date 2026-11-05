import SwiftUI

/// A split's 8 pt gap: a 16 pt hit area with the resize pointer, a grip on hover (gorex's 36 × 3 pt, in
/// `Look.grip`), a drag that moves the split live and sends on release, a double-click for 0.5, and an adjustable
/// accessibility element (5 % steps).
struct SplitDivider: View {
    let divider: Parts.Divider
    /// The app's ratio while dragged or sent, until herdr's snapshot shows its own.
    @Binding var held: Double?
    let page: Page
    let tabID: String
    let label: String
    @State private var hovering = false
    @Environment(\.look) private var look
    /// The ratio when the drag began.
    @State private var start: Double?
    /// The last change asked for, and the last one sent: only the latest goes, and `held` stays until its snapshot.
    @State private var asked = 0
    @State private var sent = 0

    private var right: Bool {
        divider.right
    }

    private var ratio: Double {
        held ?? divider.ratio
    }

    var body: some View {
        Color.clear
            .frame(width: right ? gap : nil, height: right ? nil : gap)
            .overlay {
                Capsule().fill(look.grip)
                    .frame(width: right ? 3 : 36, height: right ? 36 : 3)
                    .opacity(hovering || start != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: hovering || start != nil)
            }
            .overlay {
                Color.clear.contentShape(.rect)
                    .frame(width: right ? 16 : nil, height: right ? nil : 16)
                    .pointerStyle(right ? .columnResize : .rowResize)
                    .onHover { hovering = $0 }
                    // Global: the divider moves under the pointer, so its own space would move too.
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
                        hold(dragged(drag))
                    }.onEnded { drag in
                        // From the gesture: a snapshot during the drag may have dropped `held`.
                        send(hold(dragged(drag)))
                        start = nil
                    })
                    .onTapGesture(count: 2) { send(hold(0.5)) }
                    .accessibilityElement()
                    .accessibilityLabel(label)
                    // As the cards: a plain element shows XCUITest no value.
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityValue("\(Int((ratio * 100).rounded()))%")
                    .accessibilityIdentifier("divider.\(tabID).\(divider.id)")
                    .accessibilityAdjustableAction { direction in
                        send(hold(ratio + (direction == .increment ? 0.05 : -0.05)))
                    }
            }
            .onChange(of: divider.ratio) {
                if sent == asked {
                    held = nil
                }
            }
            // Its split closed: a later split at the same path must not take its ratio.
            .onDisappear { held = nil }
    }

    /// The ratio to herdr (D10). Held until the snapshot shows it; dropped when herdr refused it, or when herdr
    /// already has it (no snapshot change would drop it then).
    private func send(_ value: Double) {
        // herdr has it already, and no other change is on its way.
        guard sent != asked || abs(value - divider.ratio) > 0.0005 else {
            held = nil
            return
        }
        asked += 1
        let change = asked
        Task {
            // After a write in flight (a quick second change), not refused as busy.
            while page.store.writing {
                try? await Task.sleep(for: .milliseconds(50))
            }
            // A newer change replaced it while it waited.
            guard change == asked else { return }
            let done = await page.store.setRatio(tab: tabID, path: divider.path, ratio: value)
            sent = change
            if !done {
                held = nil
            }
        }
    }

    /// The ratio the drag points at, from the ratio when it began.
    private func dragged(_ drag: DragGesture.Value) -> Double {
        let from = start ?? ratio
        start = from
        return from + (right ? drag.translation.width : drag.translation.height) / max(divider.total, 1)
    }

    /// In herdr's 0.1–0.9, so the view shows what herdr keeps.
    @discardableResult
    private func hold(_ value: Double) -> Double {
        let clamped = min(max(value, 0.1), 0.9)
        held = clamped
        return clamped
    }
}
