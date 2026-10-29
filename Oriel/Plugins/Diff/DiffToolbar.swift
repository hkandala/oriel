import HerdrKit
import SwiftUI

/// A diff card's second row: the source (Uncommitted or one of the last 50 commits), Unified or Side by Side, the
/// file list, previous and next change. A new source rewrites the pane's label; the page loads again with it.
struct DiffToolbar: View {
    let plugin: Plugin
    let page: Page
    @State private var commits: [Git.Commit] = []
    @Environment(\.look) private var look

    var body: some View {
        @Bindable var web = plugin.web
        let id = "pane.\(plugin.paneID).diff", (root, source) = plugin.label.diff
        HStack(spacing: 6) {
            Menu {
                Picker("Source", selection: Binding(get: { source }, set: { pick(root, $0) })) {
                    Text("Uncommitted").tag("uncommitted")
                    Divider()
                    // A commit from a link may be older than the list.
                    if source != "uncommitted", !commits.contains(where: { $0.hash == source }) {
                        Text(source.prefix(7)).tag(source)
                    }
                    ForEach(commits, id: \.hash) { commit in
                        Text("\(commit.hash.prefix(7))  \(commit.subject)").tag(commit.hash)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(plugin.label.title == "Changes" ? "Uncommitted" : plugin.label.title)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityIdentifier("\(id).source")
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
        .task(id: root) {
            let usable = await gitUsable.value
            guard page.store.machine.isRemote || usable else { return }
            commits = await (try? Git.log(root, exec: page.store.machine.exec()).prefix(50)).map(Array.init) ?? []
        }
    }

    private func pick(_ root: String, _ source: String) {
        let label = PaneLabel(plugin: plugin.label.plugin, iid: plugin.label.iid, arg: "\(root) \(source)")
        Task { await page.store.rename(pane: plugin.paneID, label: label.text) }
    }
}
