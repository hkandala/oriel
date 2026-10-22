import HerdrKit
import SwiftUI

/// The gap between cards, the one fixed size.
let gap: CGFloat = 8

extension Animation {
    /// Rex's tab spring (stiffness 520, damping 46, critically damped).
    static let tab = Animation.spring(response: 0.28, dampingFraction: 1)
}

/// The appearance setting (D44): Auto follows macOS.
enum Appearance: String {
    case auto, light, dark
}

/// The interface style setting (D44): Glass blurs the desktop behind the window, Classic is an opaque window.
enum InterfaceStyle: String {
    case glass, classic
}

/// Every color the views draw, for one interface style and appearance (D44). Values from Rex's Glass (Modern) and
/// Classic (System) material files, tuned by eye.
struct Look {
    let style: InterfaceStyle
    let dark: Bool

    /// Glass: over the behind-window blur, blended `overlay` under `window`; it darkens the blur in dark.
    var backdrop: Color {
        dark ? .black.opacity(0.6) : .clear
    }

    /// Glass: the tint over the behind-window blur. Classic: the whole window.
    var window: Color {
        pick(Color(white: 0x1E / 255).opacity(0.5), .white.opacity(0.5),
             Color(white: 0x1E / 255), Color(white: 0xF6 / 255))
    }

    var cardFill: Color {
        // Classic dark: #222 on #1e1e1e, as in Rex.
        pick(.white.opacity(0.04), .white.opacity(0.1), .white.opacity(0.018), .white.opacity(0.6))
    }

    /// Over `cardFill` on the card that has the keyboard: light cards end at white 0.7 (Glass) and 0.8 (Classic).
    var keyboardFill: Color {
        pick(.white.opacity(0.05), .white.opacity(2 / 3), .black.opacity(0.1), .white.opacity(0.5))
    }

    /// A 0.7 pt rim inside the card's edge, drawn `plusLighter`; Glass only.
    var rim: Color {
        pick(.white.opacity(0.1), .white.opacity(0.04), .clear, .clear)
    }

    /// The stroke just outside the card's edge.
    func edge(keyboard: Bool) -> (color: Color, width: CGFloat) {
        keyboard
            ? pick((.white.opacity(0.1), 1), (.black.opacity(0.07), 1), (.white.opacity(0.1), 0.8),
                   (.black.opacity(0.18), 0.8))
            : pick((.black.opacity(0.5), 1), (.black.opacity(0.05), 1), (.white.opacity(0.07), 0.7),
                   (.black.opacity(0.12), 0.7))
    }

    var cardShadow: ShadowStyle {
        let none = ShadowStyle.drop(color: .clear, radius: 0)
        return pick(none, .drop(color: .black.opacity(0.1), radius: 5, y: 2), none,
                    .drop(color: .black.opacity(0.06), radius: 4, y: 1))
    }

    var working: Color {
        dark ? Color(hex: 0x58A6FF) : Color(hex: 0x0667D8)
    }

    var needsYou: Color {
        dark ? Color(hex: 0xD29922) : Color(hex: 0x9D5C00)
    }

    private func pick<Value>(_ glassDark: Value, _ glassLight: Value, _ classicDark: Value,
                             _ classicLight: Value) -> Value
    {
        switch (style, dark) {
        case (.glass, true): glassDark
        case (.glass, false): glassLight
        case (.classic, true): classicDark
        case (.classic, false): classicLight
        }
    }
}

extension EnvironmentValues {
    @Entry var look = Look(style: .glass, dark: true)
}

private extension Color {
    /// `#rrggbb` from the icon catalog; the neutral tile when missing.
    init(hex: String?) {
        self.init(hex: hex.flatMap { Int($0.dropFirst(), radix: 16) } ?? 0x2B2D31)
    }

    init(hex: Int) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A pane card's surface: its fill, a rim in Glass, the stroke outside its edge and, in light, a shadow.
struct CardSurface: View {
    static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    let keyboard: Bool
    @Environment(\.look) private var look

    var body: some View {
        let shape = Self.shape, edge = look.edge(keyboard: keyboard)
        shape.fill(look.cardFill.shadow(look.cardShadow))
            .overlay(shape.fill(keyboard ? look.keyboardFill : .clear))
            .overlay(shape.strokeBorder(look.rim, lineWidth: 0.7).blendMode(.plusLighter))
            .overlay(shape.inset(by: -edge.width / 2).stroke(edge.color, lineWidth: edge.width))
    }
}

/// The selected tab or row: a Liquid Glass capsule in Glass, a raised pill in Classic.
struct Pill<S: InsettableShape>: View {
    let shape: S
    @Environment(\.look) private var look

    var body: some View {
        switch (look.style, look.dark) {
        case (.glass, _):
            Color.clear.glassEffect(.regular, in: shape)
        case (.classic, true):
            shape.fill(.white.opacity(0.08))
                .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.8).blendMode(.plusLighter))
        case (.classic, false):
            shape.fill(.white)
                .overlay(shape.strokeBorder(.black.opacity(0.1)))
                .shadow(color: .black.opacity(0.15), radius: 3.5, y: 1.5)
        }
    }
}

/// ◔ working, ▲ needs you; nothing when idle. Static: no animation, so nothing redraws while agents work.
struct StatusGlyph: View {
    let status: AgentStatus
    @Environment(\.look) private var look

    var body: some View {
        switch status {
        case .working:
            Text("◔").foregroundStyle(look.working).accessibilityLabel("working")
        case .blocked:
            Text("▲").foregroundStyle(look.needsYou).accessibilityLabel("needs you")
        default:
            EmptyView()
        }
    }
}

/// The program icon catalog (`resources/icons/catalog.json`, bundled).
let programIcons: [ProgramIcon] = {
    // Without it every pane would draw the neutral tile: loud in a debug build.
    guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
        assertionFailure("no catalog.json in the app")
        return []
    }
    do {
        return try JSONDecoder().decode([ProgramIcon].self, from: Data(contentsOf: url))
    } catch {
        assertionFailure("program icon catalog: \(error)")
        return []
    }
}()

/// A program's colored tile, as in Rex: the catalog's tile and glyph colors, a dark outline and a faint highlight
/// at the top.
struct ProgramTile: View {
    let icon: String
    /// The placeholder's: the program's first letter.
    var letter: String?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let colors = programIcons.first { $0.id == icon }?.tile
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        // The glyphs carry their own padding in a 24 pt box.
        ProgramMark(icon: icon, letter: letter, size: 17)
            .foregroundStyle(Color(hex: colors?.glyph))
            .frame(width: 22, height: 18)
            .background(Color(hex: colors?.background), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top,
                                                       endPoint: .center), lineWidth: 1))
            .overlay(shape.inset(by: -0.5 / scale).stroke(.black.opacity(0.45), lineWidth: 1 / scale))
            .accessibilityHidden(true)
    }
}

/// The program's glyph alone, for card headers.
struct ProgramGlyph: View {
    let icon: String
    var letter: String?

    var body: some View {
        ProgramMark(icon: icon, letter: letter, size: 16).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

/// The catalog's template image, or the placeholder's letter.
private struct ProgramMark: View {
    let icon: String
    let letter: String?
    let size: CGFloat

    var body: some View {
        if icon == "placeholder", let letter {
            Text(letter).font(.system(size: size * 0.65, weight: .bold, design: .rounded))
        } else {
            Image("program.\(icon)").resizable().frame(width: size, height: size)
        }
    }
}

/// A tab's panes as overlapping tiles, the first in front and each next one 4 pt to the right behind it. A ring cut
/// around each tile in front keeps the layers apart on any background.
struct IconStack: View {
    let panes: [HostStore.Pane]

    var body: some View {
        ZStack(alignment: .leading) {
            // Back to front.
            ForEach(Array(panes.enumerated()).reversed(), id: \.element.id) { index, pane in
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 24, height: 20)
                        .blendMode(.destinationOut)
                    ProgramTile(icon: pane.iconID, letter: pane.letter)
                }
                .frame(width: 22, height: 18)
                .offset(x: CGFloat(index) * 4)
            }
        }
        .compositingGroup()
        .frame(width: 22 + CGFloat(max(panes.count - 1, 0)) * 4, alignment: .leading)
    }
}

/// Rows, buttons and capsules: flat at rest, a soft fill under the pointer, a raised pill when selected.
struct ChromeStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = 8
    /// The selected fill; the look's pill when nil.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        Chrome(style: self, configuration: configuration)
    }

    struct Chrome: View {
        let style: ChromeStyle
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
            configuration.label
                .contentShape(shape)
                .background {
                    if !style.selected {
                        // The same in both styles, and they follow the appearance by themselves (D44).
                        shape.fill(.primary.opacity(configuration.isPressed ? 0.08 : hovering && enabled ? 0.05 : 0))
                    } else if let tint = style.tint {
                        shape.fill(tint)
                    } else {
                        Pill(shape: shape)
                    }
                }
                .opacity(enabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// A row of the session list and the palette: a symbol (or a pane's program tile), a title, and a shortcut or
/// hint on the right.
struct MenuRow: View {
    var symbol: String?
    var pane: HostStore.Pane?
    let title: String
    var detail = ""
    /// On the accent pill.
    var selected = false

    var body: some View {
        HStack(spacing: 8) {
            if let pane {
                ProgramTile(icon: pane.iconID, letter: pane.letter)
            } else {
                // As wide as a program tile, so the titles line up.
                Image(systemName: symbol ?? "circle").opacity(symbol == nil ? 0 : 1).frame(width: 22)
                    .accessibilityHidden(true)
            }
            // A long typed name keeps both ends, and takes the free space before the detail does.
            Text(title).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Spacer(minLength: 4)
            // Readable on the accent pill too.
            Text(detail).foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}

/// One line that fades out over its last 16 pt when it does not fit, instead of an ellipsis.
struct FadeText: View {
    let text: Text

    var body: some View {
        ViewThatFits(in: .horizontal) {
            text.fixedSize()
            text.fixedSize().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                    }
                }
        }
        .lineLimit(1)
    }
}

/// An SF Symbol button for the title bar, the sidebar and card headers.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ChromeStyle(radius: 7))
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// A panel over the window (the session list, the palette): a click outside it or Esc closes it.
    func floatingPanel(open: Binding<Bool>, alignment: Alignment) -> some View {
        Color.clear.contentShape(.rect).onTapGesture { open.wrappedValue = false }
            .overlay(alignment: alignment) {
                self
                #if os(macOS)
                    .onExitCommand { open.wrappedValue = false }
                #endif
            }
    }
}

extension String {
    /// Whether this label passes a typed filter: trimmed, case and accent blind, empty passes all.
    func matches(_ filter: String) -> Bool {
        let filter = filter.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty || localizedStandardContains(filter)
    }
}
