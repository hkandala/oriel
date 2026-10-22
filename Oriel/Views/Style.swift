import HerdrKit
import SwiftUI

/// The gap between cards, the one fixed size.
let gap: CGFloat = 8

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

/// The small terminal tile on tabs and rows.
struct IconTile: View {
    var body: some View {
        Text(">_")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(red: 0.6, green: 0.88, blue: 0.62))
            .frame(width: 22, height: 18)
            .background(.black.opacity(0.55), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.09)))
            .accessibilityHidden(true)
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
                .onHover { hovering = $0 }
        }
    }
}

/// A row of the session list and the palette: a symbol, a title, and a shortcut or hint on the right.
struct MenuRow: View {
    var symbol: String?
    let title: String
    var detail = ""
    /// On the accent pill.
    var selected = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol ?? "circle").opacity(symbol == nil ? 0 : 1).frame(width: 18)
                .accessibilityHidden(true)
            // A long typed name keeps both ends, and takes the free space before the detail does.
            Text(title).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Spacer(minLength: 4)
            // Readable on the accent pill too.
            Text(detail).foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

/// The filter field of the sidebar and the session list. Until clicked (or with `autofocus`) it is plain text,
/// so the window has no text field to hand the keyboard to at launch; keys belong to the panes.
struct FilterField: View {
    let prompt: String
    @Binding var text: String
    let identifier: String
    var autofocus = false
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if editing || autofocus || !text.isEmpty {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .task {
                        // ponytail: focus asked for as the field appears is dropped (AppKit has not made it a
                        // key view yet), and a single later ask was sometimes dropped too (⌘K, then typing went
                        // nowhere); ask every 50 ms until it holds, for up to 1 s. Upgrade: an AppKit field that
                        // takes first responder in viewDidMoveToWindow.
                        for _ in 0 ..< 20 where !focused {
                            try? await Task.sleep(for: .milliseconds(50))
                            focused = true
                        }
                    }
                    .onChange(of: focused) { editing = focused }
                    .accessibilityIdentifier(identifier)
            } else {
                // A button, not a field: it can't take the keyboard at launch, and VoiceOver can press it.
                Button { editing = true } label: {
                    Text(prompt).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.07), in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { editing = true }
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
