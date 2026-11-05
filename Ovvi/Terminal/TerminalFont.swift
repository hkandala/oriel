import AppKit
import GhosttyTerminal

/// The text size, the Terminal settings and the one configuration every surface shares.
extension PaneTerminal {
    /// The default text size (design: theme and accessibility).
    static let fontSize = 13
    static let fontSizes = 8 ... 32

    /// `keybind = clear`: app shortcuts reach the menu. Transparent, so the card shows through.
    /// No padding, so cells map from the view's origin; no scrollback, herdr keeps it. The font and the Terminal
    /// settings come with the text size (`configure`).
    ///
    /// Selections keep each cell's own text color over a macOS-like blue. libghostty's Alabaster and Afterglow set
    /// only a selection background, and Ghostty then draws selected text in the window background: `#212121` on
    /// `#303030` in dark, `#F7F7F7` on `#C9D0D9` in light. Light: macOS's selected-text blue;
    /// dark: the system blue at 0.25 over Afterglow's background, for 7.6 to 1 under Afterglow's text (macOS's dark
    /// `#3F638B` gives 4.0, under WCAG's 4.5). Reverse-video cells still draw in the background color
    /// (Ghostty's rule).
    /// ponytail: always blue; follow the accent color (`NSColor.selectedTextBackgroundColor`) if users ask.
    static let controller = TerminalController(theme: TerminalTheme(
        light: .alabaster.selectionBackground("B3D7FF").selectionForeground("cell-foreground"),
        dark: .afterglow.selectionBackground("1B3A58").selectionForeground("cell-foreground"),
    )) {
        $0.withCustom("keybind", "clear")
        $0.withBackgroundOpacity(0)
        $0.withWindowPaddingX(0)
        $0.withWindowPaddingY(0)
        $0.withCustom("window-padding-balance", "false")
        $0.withCustom("scrollback-limit", "0")
    }

    /// The system monospaced font (SF Mono) rather than libghostty's own JetBrains Mono.
    static let systemFont = NSFont.monospacedSystemFont(ofSize: 0, weight: .regular).familyName ?? "Menlo"

    /// The fixed-pitch families on this Mac, for Settings ▸ Terminal ▸ Font; not the hidden system ones (`.SF…`).
    static var fonts: [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        // SF Mono, when installed, is the first choice already.
        return Set(names.compactMap { NSFont(name: $0, size: 0)?.familyName }
            .filter { !$0.hasPrefix(".") && $0 != "SF Mono" }).sorted()
    }

    /// The font and size `configure` last gave the terminals.
    private static var lastGrid = ""

    /// Reads the stored size, not a caller's copy: SwiftUI keeps a shortcut's first action.
    static func stepFontSize(_ step: Int) {
        let defaults = UserDefaults.standard
        let size = clamped(defaults.object(forKey: "fontSize") as? Int ?? fontSize) + step
        defaults.set(clamped(size), forKey: "fontSize")
    }

    /// Every surface takes the text size and the Terminal settings (ui/settings#terminal) at once, and its stream
    /// stays open; a new font or size changes its grid, so the card resizes its PTY. Streaming cards hold their
    /// picture first (`hold`). Read from the defaults, so one call serves every setting.
    static func configure() {
        let settings = AppSettings(), grid = "\(settings.terminalFont) \(settings.fontSize)"
        // Only a new font or size changes the grid: hold the pictures for it alone.
        if grid != lastGrid {
            PaneViewRegistry.recent.forEach { $0.hold() }
            lastGrid = grid
        }
        controller.setTerminalConfiguration(TerminalConfiguration {
            $0.withFontFamily(settings.terminalFont.isEmpty ? systemFont : settings.terminalFont)
            $0.withFontSize(Float(clamped(settings.fontSize)))
            $0.withCursorStyle(settings.cursorStyle)
            // Unset, Ghostty also follows DEC mode 12; false only makes the default still. A program's DECSCUSR wins
            // either way.
            if !settings.cursorBlink {
                $0.withCursorStyleBlink(false)
            }
            // Characters on every layout by default (on CI's, libghostty sent Alt by default).
            $0.withCustom("macos-option-as-alt", settings.optionKey.ghostty)
            // The system pasteboard: libghostty's `true` writes only a selection clipboard, which nothing reads.
            if settings.copyOnSelect {
                $0.withCustom("copy-on-select", "clipboard")
            }
        })
    }

    /// In 8–32: a hand-edited default (`defaults write`) can be out of range.
    private static func clamped(_ size: Int) -> Int {
        min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
    }
}
