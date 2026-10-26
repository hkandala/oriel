import AppKit
import GhosttyTerminal

/// The text size and the one configuration every surface shares.
extension PaneTerminal {
    /// The default text size (design: theme and accessibility).
    static let fontSize = 13
    static let fontSizes = 8 ... 32

    /// `keybind = clear`: app shortcuts reach the menu. Transparent, so the card shows through.
    /// No padding, so cells map from the view's origin; no scrollback, herdr keeps it. The system
    /// monospaced font (SF Mono) rather than libghostty's own JetBrains Mono.
    ///
    /// Selections keep each cell's own text color over a macOS-like blue. libghostty's Alabaster and Afterglow set
    /// only a selection background, and Ghostty then draws selected text in the window background: `#212121` on
    /// `#303030` in dark, `#F7F7F7` on `#C9D0D9` in light (phase 29 lane C). Light: macOS's selected-text blue;
    /// dark: the system blue at 0.25 over Afterglow's background, for 7.6 to 1 under Afterglow's text (macOS's dark
    /// `#3F638B` gives 4.0, under WCAG's 4.5). Reverse-video cells still draw in the background color
    /// (Ghostty's rule).
    /// ponytail: always blue; follow the accent color (`NSColor.selectedTextBackgroundColor`) if users ask.
    static let controller = TerminalController(theme: TerminalTheme(
        light: .alabaster.selectionBackground("B3D7FF").selectionForeground("cell-foreground"),
        dark: .afterglow.selectionBackground("1B3A58").selectionForeground("cell-foreground"),
    )) {
        $0.withCustom("keybind", "clear")
        $0.withFontFamily(NSFont.monospacedSystemFont(ofSize: 0, weight: .regular).familyName ?? "Menlo")
        $0.withBackgroundOpacity(0)
        $0.withWindowPaddingX(0)
        $0.withWindowPaddingY(0)
        $0.withCustom("window-padding-balance", "false")
        $0.withCustom("scrollback-limit", "0")
        // Option types characters on every layout (on CI's, libghostty sent Alt by default).
        $0.withCustom("macos-option-as-alt", "false")
    }

    /// Reads the stored size, not a caller's copy: SwiftUI keeps a shortcut's first action (phase 11 Findings).
    static func stepFontSize(_ step: Int) {
        let defaults = UserDefaults.standard
        let size = clamped(defaults.object(forKey: "fontSize") as? Int ?? fontSize) + step
        defaults.set(clamped(size), forKey: "fontSize")
    }

    /// Every surface takes a new text size at once, and its stream stays open; its grid changes, so the
    /// card resizes its PTY. Streaming cards hold their picture first (`hold`).
    static func setFontSize(_ size: Int) {
        PaneViewRegistry.recent.forEach { $0.hold() }
        controller.setTerminalConfiguration(TerminalConfiguration { $0.withFontSize(Float(clamped(size))) })
    }

    /// In 8–32: a hand-edited default (`defaults write`) can be out of range.
    private static func clamped(_ size: Int) -> Int {
        min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
    }
}
