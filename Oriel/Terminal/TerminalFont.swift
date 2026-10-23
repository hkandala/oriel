#if os(macOS)
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
        static let controller = TerminalController {
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
        /// card resizes its PTY.
        static func setFontSize(_ size: Int) {
            controller.setTerminalConfiguration(TerminalConfiguration { $0.withFontSize(Float(clamped(size))) })
        }

        /// In 8–32: a hand-edited default (`defaults write`) can be out of range.
        private static func clamped(_ size: Int) -> Int {
            min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
        }
    }
#endif
