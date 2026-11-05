import HerdrKit
import SwiftUI

/// t3code's state icons, still and round: lucide's `circle-dashed` (Working), `circle-alert` (Needs you, and a chat's
/// Error) and `circle-check` (Done), stroked as lucide draws them (2 of 24 units, round ends). Idle draws nothing.
struct StateIcon: View {
    let state: AgentState
    var color: Color?
    @Environment(\.look) private var look

    var body: some View {
        Lucide(state: state)
            .stroke(
                color ?? state.color(look),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round),
            )
            .frame(width: 12, height: 12)
    }

    /// The shapes on lucide's 24-unit grid: a circle of radius 10 round (12, 12).
    private nonisolated struct Lucide: Shape {
        let state: AgentState

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: 12, y: 12)
            switch state {
            case .idle: return path
            case .working:
                // Eight arcs, each 21.9° (a 3.8-unit chord), centered on every 45°.
                let half = Angle.radians(asin(0.19))
                for step in 0 ..< 8 {
                    let start = Angle.degrees(Double(step) * 45) - half
                    path.move(to: CGPoint(x: 12 + 10 * cos(start.radians), y: 12 + 10 * sin(start.radians)))
                    path.addRelativeArc(center: center, radius: 10, startAngle: start, delta: half * 2)
                }
            case .needsYou:
                path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
                path.addLines([CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 12)])
                path.addLines([CGPoint(x: 12, y: 16), CGPoint(x: 12.01, y: 16)])
            case .finishedUnseen:
                path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
                path.addLines([CGPoint(x: 9, y: 12), CGPoint(x: 11, y: 14), CGPoint(x: 15, y: 10)])
            }
            return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
        }
    }
}

extension View {
    /// A state icon as one element a test reads: its word as the value.
    func stateElement(_ state: AgentState, _ id: String) -> some View {
        accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityValue(state.title)
            .accessibilityIdentifier(id)
    }
}

/// A state: its icon and word in the state's color, 11 pt medium (a card's header, an overview tile).
struct StateLabel: View {
    let text: String
    /// Whose icon: a chat's Error takes Needs you's.
    let icon: AgentState
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            StateIcon(state: icon, color: color)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(color)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityValue(text)
    }
}

/// An Agents view row's state: its icon, and for Working how long it has worked ("<1m", "3m", "1h 5m"), in the state's
/// color, on a 14 % tint with a 1 pt border at 45 % and 6 pt corners.
struct StateBox: View {
    let state: AgentState
    let since: Date?
    @Environment(\.look) private var look

    var body: some View {
        let color = state.color(look)
        HStack(spacing: 4) {
            StateIcon(state: state)
            if let since {
                TimelineView(.periodic(from: since, by: 60)) { context in
                    Text(Self.elapsed(context.date.timeIntervalSince(since))).monospacedDigit()
                }
            }
        }
        .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
        // The CSS box's padding inside its 1 pt border.
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(color.opacity(0.14), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.45)))
        .fixedSize()
    }

    /// Minutes, then hours and minutes (shorter than a chat turn's "1m 48s", `ChatHistory.duration`, to fit a sidebar
    /// row); no seconds, so the text changes once a minute.
    static func elapsed(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval)) / 60
        return minutes < 1 ? "<1m" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
