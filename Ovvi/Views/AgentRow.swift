import SwiftUI

/// An Agents view row, a 48 pt button: the program tile on line 1, then the name, then `trailing` (the state box, an
/// age); line 2 full width. Under the pointer `hover` (Pin, Resume) shows before `trailing`, as buttons of their own
/// over the row: inside the row's label, they would be part of its one accessibility element.
struct AgentRow<Hover: View, Trailing: View>: View {
    let icon: String
    var letter: String?
    let title: String
    let line2: String
    /// Needs you or an unseen finish: the name is medium; the others recede.
    var medium = false
    var lit = false
    /// The row's accessibility identifier and value.
    let id: String
    var value = ""
    let action: () -> Void
    @ViewBuilder var hover: () -> Hover
    @ViewBuilder var trailing: () -> Trailing
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                ProgramTile(icon: icon, letter: letter)
                lines {
                    Text(title).font(.system(size: 13, weight: medium ? .medium : .regular)).lineLimit(1)
                        .foregroundStyle(lit ? look.selected : look.chrome)
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
        }
        .buttonStyle(ChromeStyle(selected: lit, radius: 10))
        .accessibilityIdentifier(id)
        .accessibilityLabel("\(title), \(line2)")
        .accessibilityValue(value)
        .accessibilityAddTraits(lit ? .isSelected : [])
        // The same two lines, with only the hover buttons drawn, right before where `trailing` is.
        .overlay {
            if hovering {
                lines(line2: false) {
                    Spacer(minLength: 0)
                    hover()
                    trailing().hidden()
                }
                .padding(.horizontal, 8)
            }
        }
        .onHover { hovering = $0 }
    }

    private func lines(line2 shown: Bool = true, @ViewBuilder _ first: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // The box's and the hover buttons' height, so line 2 stays put.
            HStack(spacing: 6) { first() }.frame(height: 18)
            Text(line2).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).opacity(shown ? 1 : 0)
        }
    }
}

/// An age, where a row's state box goes.
struct AgeText: View {
    let date: Date
    var now = Date.now

    var body: some View {
        Text(Self.age(date, now: now)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
    }

    /// The time since `date` in a shelf: "5m", "5h", "2d", "1w".
    static func age(_ date: Date, now: Date = .now) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date))) / 60
        return switch minutes {
        case ..<60: "\(minutes)m"
        case ..<(60 * 24): "\(minutes / 60)h"
        case ..<(60 * 24 * 7): "\(minutes / 60 / 24)d"
        default: "\(minutes / 60 / 24 / 7)w"
        }
    }
}
