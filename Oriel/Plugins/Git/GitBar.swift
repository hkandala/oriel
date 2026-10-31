import HerdrKit
import SwiftUI

/// A Git card's second row: on the home, Back and Forward, the branch (a menu that switches it), then Fetch, Pull with
/// the commits behind and Push with the commits ahead; on a diff, the diff's controls (`DiffToolbar`).
struct GitBar: View {
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look

    var body: some View {
        if plugin.label.diff.source != nil {
            DiffToolbar(plugin: plugin, page: page)
        } else {
            let repo = plugin.web.git, id = "pane.\(plugin.paneID).git"
            HStack(spacing: 6) {
                BackForward(plugin: plugin)
                branch(repo, id: id)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    action("fetch", "arrow.clockwise", "Fetch", count: 0, repo.fetch)
                    action("pull", "arrow.down", "Pull", count: repo.status?.behind ?? 0, repo.pull)
                    action("push", "arrow.up", "Push", count: repo.status?.ahead ?? 0, repo.push)
                }
                .foregroundStyle(look.paneButton)
                .disabled(repo.failure != nil || repo.running != nil)
            }
        }
    }

    /// The checked-out branch; its menu lists the local branches, then the remote ones with no local branch.
    private func branch(_ repo: GitRepo, id: String) -> some View {
        Menu {
            let local = repo.branches.filter { !$0.remote }, remote = repo.branches.filter(\.remote)
            ForEach(local, id: \.name) { branch in
                Toggle(branch.name, isOn: Binding(get: { branch.current }, set: { _ in repo.switchTo(branch) }))
            }
            if !remote.isEmpty {
                Divider()
                Section("Remote") {
                    ForEach(remote, id: \.name) { branch in
                        Button(branch.name) { repo.switchTo(branch) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if repo.running == "switch" {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.triangle.branch")
                }
                Text(repo.status?.branch ?? "—").lineLimit(1).truncationMode(.middle)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .disabled(repo.branches.isEmpty || repo.running != nil)
        .accessibilityIdentifier("\(id).branch")
    }

    /// A 22 pt button with its count after the symbol, a spinner while it runs.
    private func action(_ name: String, _ symbol: String, _ help: String, count: Int,
                        _ run: @escaping () -> Void) -> some View
    {
        Button(action: run) {
            HStack(spacing: 2) {
                if plugin.web.git.running == name {
                    ProgressView().controlSize(.mini).frame(width: 14)
                } else {
                    Image(systemName: symbol).font(.system(size: 11)).frame(width: 14)
                }
                if count > 0 {
                    Text("\(count)").font(.system(size: 11).monospacedDigit())
                }
            }
            .padding(.horizontal, 4)
            .frame(minWidth: 22, minHeight: 22)
        }
        .buttonStyle(ChromeStyle(radius: 5.5))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityIdentifier("pane.\(plugin.paneID).git.\(name)")
    }
}
