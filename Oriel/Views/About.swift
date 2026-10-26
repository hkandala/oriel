import SwiftUI

/// Oriel's About window (phase 33: the system panel showed the credits as a dump of text): the icon, name and version,
/// then one line per credit in a glass card (its name links its home page, its license on the right), and a button
/// that opens the full license texts, `Acknowledgements.txt` in the app.
struct About: View {
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dismiss) private var dismiss

    // A group, then each credit: name, license, home page.
    // swiftlint:disable:next large_tuple
    private static let credits: [(group: String, lines: [(name: String, license: String, url: String?)])] = [
        ("Terminal", [("Ghostty", "MIT", "https://ghostty.org"),
                      // FreeType, Oniguruma, libpng, zlib and the others, in Acknowledgements.txt.
                      ("Ghostty's libraries", "Various", nil),
                      ("libghostty-spm", "MIT", "https://github.com/Lakr233/libghostty-spm"),
                      ("DisplayLink", "MIT", "https://github.com/Lakr233/DisplayLink"),
                      ("bash-preexec", "MIT", "https://github.com/rcaloras/bash-preexec")]),
        ("Program Icons", [("Simple Icons", "CC0-1.0", "https://simpleicons.org"),
                           ("Lobe Icons", "MIT", "https://github.com/lobehub/lobe-icons"),
                           ("Phosphor Icons", "MIT", "https://phosphoricons.com"),
                           ("Devicon", "MIT", "https://devicon.dev"),
                           ("oh-my-pi", "MIT", "https://github.com/can1357/oh-my-pi"),
                           ("aider", "Apache-2.0", "https://github.com/Aider-AI/aider"),
                           ("jj", "Apache-2.0", "https://github.com/jj-vcs/jj"),
                           ("Drawn for Oriel", "CC0-1.0", nil)]),
    ]

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let info = { (key: String) in Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Oriel").font(.system(size: 20, weight: .semibold))
                Text("Version \(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(Self.credits, id: \.group) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.group).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.leading, 12)
                    VStack(spacing: 0) {
                        ForEach(group.lines, id: \.name) { line in
                            HStack {
                                if let url = line.url.flatMap(URL.init(string:)) {
                                    Link(line.name, destination: url)
                                } else {
                                    Text(line.name)
                                }
                                Spacer()
                                Text(line.license).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .accessibilityElement(children: .contain).accessibilityIdentifier("about.\(line.name)")
                        }
                    }
                    .padding(.vertical, 5)
                    .floatingGlass(in: .rect(cornerRadius: 12))
                }
            }
            .font(.system(size: 13))
            VStack(spacing: 10) {
                if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                    Button("License Texts") { NSWorkspace.shared.open(url) }.buttonStyle(.glass)
                        .accessibilityIdentifier("about.licenses")
                }
                Text("Brand marks belong to their owners.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 20)
        .frame(width: 340)
        .containerBackground(for: .window) { WindowBackground(look: look) }
        .windowMinimizeBehavior(.disabled)
        // ⌘W closes it, as it does the system's About panel: the menu bar's ⌘W is a main window's Close Pane.
        .background { Button("Close") { dismiss() }.keyboardShortcut("w").opacity(0).accessibilityHidden(true) }
    }
}
