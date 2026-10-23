import HerdrKit
import SwiftUI

/// The gap between cards, the one fixed size.
nonisolated let gap: CGFloat = 8

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

    /// Glass: the tint over the behind-window blur (light: Rex's Modern 0.7, so it depends less on the desktop).
    /// Classic: the whole window.
    var window: Color {
        pick(Color(white: 0x1E / 255).opacity(0.5), .white.opacity(0.7),
             Color(white: 0x1E / 255), Color(white: 0xF6 / 255))
    }

    var cardFill: Color {
        // Glass dark: Rex's pane backdrop darkens the window under cards (6 steps on a #2c window). Classic dark: #222
        // on #1e1e1e, as in Rex.
        pick(.black.opacity(0.14), .white.opacity(0.1), .white.opacity(0.018), .white.opacity(0.6))
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
            ? pick((.black.opacity(0.5), 1), (.black.opacity(0.1), 1), (.white.opacity(0.1), 0.8),
                   (.black.opacity(0.18), 0.8))
            : pick((.black.opacity(0.5), 1), (.black.opacity(0.05), 1), (.clear, 0),
                   (.black.opacity(0.12), 0.7))
    }

    /// A divider's grip: gorex's muted icon color at 0.6.
    var grip: Color {
        Color.secondary.opacity(0.6)
    }

    /// Glass light only, as in Rex (Classic light has none).
    var cardShadow: ShadowStyle? {
        style == .glass && !dark ? .drop(color: .black.opacity(0.1), radius: 5, y: 2) : nil
    }

    /// The tab bar's track; none in Classic dark, as in Rex.
    var track: Color {
        style == .classic && dark ? .clear : .primary.opacity(0.05)
    }

    /// Text and glyphs of the title row and the sidebar, a step dimmer than primary text as in Rex.
    var chrome: Color {
        dark ? .white.opacity(0.65) : .black.opacity(0.65)
    }

    /// A divider between tabs, as in Rex.
    var divider: Color {
        dark ? .white.opacity(0.17) : .black.opacity(0.14)
    }

    /// The selected tab's and workspace row's title.
    var selected: Color {
        dark ? .white.opacity(0.9) : .black.opacity(0.9)
    }

    /// A card header's buttons, dimmer than the title row's.
    var paneButton: Color {
        dark ? .white.opacity(0.33) : .black.opacity(0.33)
    }

    var working: Color {
        dark ? Color(hex: 0x58A6FF) : Color(hex: 0x0667D8)
    }

    var needsYou: Color {
        dark ? Color(hex: 0xD29922) : Color(hex: 0x9D5C00)
    }

    /// Also a workspace row's ↑ahead.
    var finished: Color {
        dark ? Color(hex: 0x3FB950) : Color(hex: 0x116329)
    }

    /// Also a workspace row's ↓behind.
    var error: Color {
        dark ? Color(hex: 0xF85149) : Color(hex: 0xCF222E)
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

extension Color {
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
        shape.fill(look.cardFill)
            // On an opaque copy cut out under the card: on the translucent fill it would be as faint as the fill.
            .background {
                if let shadow = look.cardShadow {
                    // An overlay did not cut (it darkened the card by about black 0.1); a ZStack does.
                    ZStack { shape.fill(Color.black.shadow(shadow)); shape.fill(.black).blendMode(.destinationOut) }
                        .compositingGroup()
                }
            }
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
            // Rex's flat #292929 on #1e1e1e.
            shape.fill(.white.opacity(0.045))
        case (.classic, false):
            shape.fill(.white)
                .overlay(shape.strokeBorder(.black.opacity(0.1)))
                .shadow(color: .black.opacity(0.15), radius: 3.5, y: 1.5)
        }
    }
}

/// Rows, buttons and capsules: flat at rest, a soft fill under the pointer, a raised pill when selected.
struct ChromeStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = 8
    /// How far inside the hit area the fills are drawn (a tab's capsule inside its track).
    var inset: CGFloat = 0
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
            let full = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
            let shape = full.inset(by: style.inset)
            configuration.label
                .contentShape(full)
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
    var state: AgentState?
    let title: String
    var detail = ""
    /// On the accent pill.
    var selected = false
    var height: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            if let pane {
                ProgramTile(icon: pane.iconID, letter: pane.letter)
            } else if let state {
                StateIcon(state: state).frame(width: 22)
            } else {
                // As wide as a program tile, so the titles line up.
                Image(systemName: symbol ?? "circle").opacity(symbol == nil ? 0 : 1).frame(width: 22)
                    .accessibilityHidden(true)
            }
            // A long typed name keeps both ends, and takes the free space before the detail does.
            Text(title).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Spacer(minLength: 4)
            // Readable on the accent pill; a long branch gives way to the title.
            Text(detail).foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary).lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(height: height)
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

/// An SF Symbol button for the title bar, the sidebar and card headers. Its tooltip and VoiceOver label say the action
/// and its shortcut ("New Tab ⌘T").
struct IconButton: View {
    let symbol: String
    let help: String
    var key: KeyboardShortcut?
    var size: CGFloat = 28
    /// Accent on a faint accent circle (a zoomed card's Restore), as in Rex.
    var accent = false
    let action: () -> Void

    var body: some View {
        let help = key.map { "\(help) \($0.glyphs)" } ?? help
        Button(action: action) {
            Image(systemName: symbol)
                .fontWeight(.medium)
                // The surrounding style: the look's chrome, or a card header's buttons.
                .foregroundStyle(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background {
                    if accent {
                        Circle().fill(.tint.opacity(0.15))
                    }
                }
        }
        .buttonStyle(ChromeStyle(radius: size / 4))
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
