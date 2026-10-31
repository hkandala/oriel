import SwiftUI

/// One line that fades out over its last 16 pt when it does not fit, instead of an ellipsis.
struct FadeText: View {
    let text: Text

    var body: some View {
        ViewThatFits(in: .horizontal) {
            text.fixedSize()
            text.fixedSize().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .fadeEdges(.horizontal, start: 0, end: 16)
        }
        .lineLimit(1)
    }
}

/// An SF Symbol button. Its tooltip and VoiceOver label say the action and its shortcut ("New Tab ⌘T").
struct IconButton: View {
    let symbol: String
    let help: String
    var key: KeyboardShortcut?
    var size: CGFloat = 28
    /// A muted accent glyph on a faint accent circle (a zoomed card's Restore), as in Rex.
    var accent = false
    let action: () -> Void

    var body: some View {
        let help = key.map { "\(help) \($0.glyphs)" } ?? help
        Button(action: action) {
            Image(systemName: symbol)
                // 22 pt buttons (card headers, the find bar): Rex's 11 pt regular glyphs.
                .font(size < 28 ? .system(size: 11) : .body.weight(.medium))
                // The surrounding style: the look's chrome, or a card header's buttons.
                .foregroundStyle(accent ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background {
                    if accent {
                        Circle().fill(.tint.opacity(0.07))
                    }
                }
        }
        .buttonStyle(ChromeStyle(radius: size / 4))
        .help(help)
        .accessibilityLabel(help)
    }
}
