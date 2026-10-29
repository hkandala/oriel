import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

/// File's row 2: the jump bar, `folder › file › the scopes around the caret`.
struct JumpBar: View {
    let plugin: Plugin

    var body: some View {
        let path = plugin.label.arg as NSString, folder = (path.deletingLastPathComponent as NSString).lastPathComponent
        let symbol = plugin.web.symbol, chevron = Text(" › ").foregroundStyle(.tertiary)
        let file = Text("\(Text(folder).foregroundStyle(.secondary))\(chevron)\(path.lastPathComponent)")
        let shown = symbol.isEmpty ? file : Text("\(file)\(chevron)\(symbol)")
        shown.fontWeight(.regular).lineLimit(1).truncationMode(.middle)
            .accessibilityValue([folder, path.lastPathComponent, symbol].filter { !$0.isEmpty }
                .joined(separator: " › "))
            .accessibilityIdentifier("pane.\(plugin.paneID).jump")
    }
}

/// Preview's row 2: the path, a PDF's page, and zoom for images and PDFs, which the page applies.
struct PreviewBar: View {
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        let id = "pane.\(plugin.paneID)", path = plugin.label.arg
        Text(path).foregroundStyle(.secondary).fontWeight(.regular).lineLimit(1).truncationMode(.middle)
            .accessibilityIdentifier("\(id).path")
        Spacer(minLength: 0)
        if !plugin.web.page.isEmpty {
            Text(plugin.web.page).foregroundStyle(.secondary).fontWeight(.regular).monospacedDigit()
                .accessibilityIdentifier("\(id).page")
        }
        let type = UTType(filenameExtension: (path as NSString).pathExtension)
        if type.map({ $0.conforms(to: .image) || $0.conforms(to: .pdf) }) == true {
            HStack(spacing: 0) {
                zoom("fit", "arrow.down.right.and.arrow.up.left", "Zoom to Fit")
                zoom("actual", "1.magnifyingglass", "Actual Size")
                zoom("out", "minus.magnifyingglass", "Zoom Out")
                zoom("in", "plus.magnifyingglass", "Zoom In")
            }
            .foregroundStyle(look.paneButton)
        }
    }

    private func zoom(_ step: String, _ symbol: String, _ help: String) -> some View {
        IconButton(symbol: symbol, help: help, size: 22) { plugin.web.send(["op": "zoom", "to": step]) }
            .accessibilityIdentifier("pane.\(plugin.paneID).zoom.\(step)")
    }
}
