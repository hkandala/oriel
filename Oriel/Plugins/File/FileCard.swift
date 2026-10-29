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
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .plainText
        let parts = [
            (Image(systemName: "folder.fill"), folder),
            (Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable(), name),
            (Image(systemName: "curlybraces"), file.symbol),
        ].filter { !$0.1.isEmpty }
        HStack(spacing: 4) {
            ForEach(parts.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Label {
                    Text(parts[index].1).lineLimit(1)
                } icon: {
                    parts[index].0.scaledToFit().frame(width: 14, height: 14)
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(index == parts.count - 1 ? .primary : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Jump Bar")
        .accessibilityValue(parts.map(\.1).joined(separator: " › "))
        .accessibilityIdentifier("pane.\(plugin.paneID).jump")
        if file.readOnly {
            Text("Read Only").foregroundStyle(.secondary).fixedSize()
                .accessibilityIdentifier("pane.\(plugin.paneID).read-only")
        }
    }
}
