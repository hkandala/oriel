import HerdrKit
import SwiftUI

/// A workspace's state in a menu row: its `StateLabel` icon, or a gray ring for an idle agent; a faint dot without
/// an agent.
struct StateIcon: View {
    let state: AgentState?
    @Environment(\.look) private var look

    var body: some View {
        Group {
            switch state {
            case .idle: Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 7, height: 7)
            case let .some(state):
                StateSymbol(name: state.symbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(state.color(look))
            // A workspace with no agent: a quiet dot, so the slot does not look missing.
            case nil: Circle().fill(.tertiary).frame(width: 4, height: 4)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// A state's symbol. Working's turns as macOS's spinner does, a symbol effect that Core Animation runs; still under
/// Reduce Motion (but with `-forceMotion`) and on a sidebar page off to the side, as the working dots.
struct StateSymbol: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreen) private var offscreen

    var body: some View {
        Image(systemName: name).symbolEffect(
            .variableColor.iterative.dimInactiveLayers.nonReversing,
            isActive: name == AgentState.working.symbol && !(reduceMotion && !Animation.forceMotion) && !offscreen,
        )
    }
}

/// A state as t3code's sidebar draws a thread's: its icon and word in the state's color, 11 pt medium. Working adds
/// its time ("Working 42s", "3m", "1h 5m").
struct StateLabel: View {
    let text: String, symbol: String, color: Color
    var since: Date?

    var body: some View {
        if let since {
            let start = Date(timeIntervalSinceReferenceDate: since.timeIntervalSinceReferenceDate.rounded(.down))
            TimelineView(Ticks(start: start)) { context in
                row("\(text) \(Self.elapsed(context.date.timeIntervalSince(start)))")
            }
        } else {
            row(text)
        }
    }

    /// Each second for the first minute, then each minute, when the text changes: from a whole second, so every label
    /// ticks in the same update, as t3code's shared tick (a hundred labels on their own phases laid out a hundred
    /// times a second).
    private struct Ticks: TimelineSchedule {
        let start: Date

        func entries(from date: Date, mode _: Mode) -> AnyIterator<Date> {
            var next = date
            return AnyIterator {
                defer {
                    let age = next.timeIntervalSince(start)
                    next = start + (age < 59 ? age.rounded(.down) + 1 : ((age / 60).rounded(.down) + 1) * 60)
                }
                return next
            }
        }
    }

    private func row(_ words: String) -> some View {
        HStack(spacing: 4) {
            StateSymbol(name: symbol)
            Text(words).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(color)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityValue(words)
    }

    /// t3code's working time: seconds, then minutes, then hours and minutes (shorter than a chat turn's "1m 48s",
    /// `ChatHistory.duration`, to fit a sidebar row).
    static func elapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval)), minutes = seconds / 60
        return seconds < 60 ? "\(seconds)s" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// The 7 pt dot on a tab's program tile's top-right for needs you and finished, cutting a 1.5 pt ring out of the
/// tile (Glass has no solid background color). In the tile's compositing group.
struct StatusBadge: View {
    let state: AgentState?
    @Environment(\.look) private var look

    var body: some View {
        if let state, state >= .finishedUnseen {
            ZStack {
                Circle().frame(width: 10, height: 10).blendMode(.destinationOut)
                Circle().fill(state.color(look)).frame(width: 7, height: 7)
            }
            .offset(x: 4, y: -4)
        }
    }
}
