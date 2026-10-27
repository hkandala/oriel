import SwiftUI

/// Oriel's About window (the system panel showed the credits as a dump of text): the icon, name and version,
/// and a button that opens every credit and license text, `Acknowledgements.txt` in the app.
struct About: View {
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let info = { (key: String) in Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Oriel").font(.system(size: 20, weight: .semibold))
            Text("Version \(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                Button("Acknowledgements") { NSWorkspace.shared.open(url) }.buttonStyle(.glass)
                    .accessibilityIdentifier("about.acknowledgements").padding(.top, 18)
            }
        }
        .padding(.horizontal, 48).padding(.bottom, 36)
        .frame(minWidth: 280)
        .containerBackground(for: .window) { WindowBackground(look: look) }
        .windowMinimizeBehavior(.disabled)
        // ⌘W closes it, as it does the system's About panel: the menu bar's ⌘W is a main window's Close Pane.
        .background { Button("Close") { dismiss() }.keyboardShortcut("w").opacity(0).accessibilityHidden(true) }
    }
}
