import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

/// The file kind's content (phase 42's spec, item 1): its text, or the preview's info view when it has none.
struct FileCard: View {
    let plugin: Plugin
    let page: Page
    /// False in an overview tile, which shows the card's text and leaves the work to the card.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let file = page.fileText(plugin)
        Group {
            if let failure = file.failure {
                FileInfo(plugin: plugin, page: page, note: failure)
            } else if file.loaded {
                CodeView(file: file, page: page)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding([.horizontal, .bottom], 6)
            } else {
                PluginLoader(kind: .file)
            }
        }
        .task(id: plugin.label.arg) {
            if isEnabled {
                await file.run()
            }
        }
    }
}

/// Row 2 of a file card: `folder › file › symbol at the caret`, as Xcode's jump bar.
struct JumpBar: View {
    let plugin: Plugin
    let file: FileText

    var body: some View {
        let folder = ((file.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let name = (file.path as NSString).lastPathComponent
        let parts = [folder, name, file.symbol].filter { !$0.isEmpty }
        HStack(spacing: 4) {
            ForEach(parts.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Label {
                    Text(parts[index]).lineLimit(1)
                } icon: {
                    switch index {
                    case 0: Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    case 1: Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (name as NSString)
                                .pathExtension) ?? .plainText))
                            .resizable().frame(width: 14, height: 14)
                    default: Image(systemName: "curlybraces").foregroundStyle(.secondary)
                    }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(index == parts.count - 1 ? .primary : .secondary)
            }
        }
        .fontWeight(.regular)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Jump Bar")
        .accessibilityValue(parts.joined(separator: " › "))
        .accessibilityIdentifier("pane.\(plugin.paneID).jump")
    }
}
