import HerdrKit
import SwiftUI

/// A Git card's second row on a diff: Back and Forward, Git Home, then Unified or Side by Side, the file list, previous
/// and next change.
struct DiffToolbar: View {
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        @Bindable var web = plugin.web
        let id = "pane.\(plugin.paneID).diff"
        HStack(spacing: 6) {
            BackForward(plugin: plugin)
            IconButton(symbol: "house", help: "Git Home", size: 22) { plugin.go(home(plugin.web.diff.root)) }
                .foregroundStyle(look.paneButton)
                .accessibilityIdentifier("\(id).home")
            Spacer(minLength: 0)
            Picker("Layout", selection: $web.split) {
                Text("Unified").tag(false)
                Text("Side by Side").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("\(id).layout")
            HStack(spacing: 0) {
                IconButton(symbol: "sidebar.left", help: web.list ? "Hide File List" : "Show File List", size: 22) {
                    web.list.toggle()
                }
                .accessibilityIdentifier("\(id).file-list")
                IconButton(symbol: "chevron.up", help: "Previous Change", size: 22) {
                    web.send(["op": "step", "by": -1])
                }
                .accessibilityIdentifier("\(id).previous")
                IconButton(symbol: "chevron.down", help: "Next Change", size: 22) {
                    web.send(["op": "step", "by": 1])
                }
                .accessibilityIdentifier("\(id).next")
            }
            .foregroundStyle(look.paneButton)
        }
    }
}

/// A Git card's home place: its root with the `/` of a folder (`PaneLabel.diff`); a diff's is `<home> <source>`.
private func home(_ root: String) -> String {
    root.hasSuffix("/") ? root : root + "/"
}
