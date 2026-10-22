#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import SwiftUI

    /// The Settings window (D62, design: Settings). Each setting is one key in the app's defaults.
    struct SettingsView: View {
        var body: some View {
            TabView {
                GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
                TerminalSettings().tabItem { Label("Terminal", systemImage: "terminal") }
            }
            .frame(width: 560)
        }
    }

    private struct GeneralSettings: View {
        var body: some View {
            Form {
                LookPickers().pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Appearance and Interface Style (D44), in Settings ▸ General and View (submenus there).
    struct LookPickers: View {
        @AppStorage("appearance") private var appearance = Appearance.dark
        @AppStorage("interfaceStyle") private var style = InterfaceStyle.glass

        var body: some View {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag(Appearance.auto)
                Text("Light").tag(Appearance.light)
                Text("Dark").tag(Appearance.dark)
            }
            Picker("Interface Style", selection: $style) {
                Text("Glass").tag(InterfaceStyle.glass)
                Text("Classic").tag(InterfaceStyle.classic)
            }
        }
    }

    private struct TerminalSettings: View {
        @AppStorage("fontFamily") private var fontFamily = ""
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize
        @AppStorage("cursorStyle") private var cursorStyle = TerminalCursorStyle.block
        @AppStorage("cursorBlink") private var cursorBlink = true
        @AppStorage("optionAsAlt") private var optionAsAlt = false
        @AppStorage("copyOnSelect") private var copyOnSelect = false
        private let families = NSFontManager.shared.availableFontFamilies
            .filter { NSFont(name: $0, size: 13)?.isFixedPitch == true }

        var body: some View {
            Form {
                Picker("Font", selection: $fontFamily) {
                    Text("System Monospaced").tag("")
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Font Size") {
                    Stepper("\(fontSize) pt", value: $fontSize, in: PaneTerminal.fontSizes)
                        .accessibilityIdentifier("settings.fontSize")
                }
                Picker("Cursor Style", selection: $cursorStyle) {
                    Text("Block").tag(TerminalCursorStyle.block)
                    Text("Bar").tag(TerminalCursorStyle.bar)
                    Text("Underline").tag(TerminalCursorStyle.underline)
                }
                Toggle("Blinking Cursor", isOn: $cursorBlink)
                Toggle("Option Key Acts as Alt", isOn: $optionAsAlt)
                Toggle("Copy on Select", isOn: $copyOnSelect)
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
#endif
