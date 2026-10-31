import HerdrKit
import SwiftUI

/// Plugins (future-work/plugins, decision 5), a glass panel over the window like Open Session: a source to install
/// (`npm:`, `git:` or a folder's path), Reload Plugins, and every plugin with its name, version and source, and
/// Update, Reload and Remove. Esc or a click outside closes it.
struct PluginsPanel: View {
    @State private var source = ""
    @FocusState private var focused: Bool

    var body: some View {
        let installs = PluginInstalls.shared, typed = source.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("npm:package, git:repository or a folder", text: $source).focused($focused)
                    .focusSoon($focused).dialogField().onSubmit(install)
                    .accessibilityLabel("Source").accessibilityIdentifier("plugins.source")
                if let busy = installs.busy[typed] {
                    ProgressView().controlSize(.small)
                    Text(busy).foregroundStyle(.secondary).accessibilityIdentifier("plugins.busy")
                } else {
                    Button("Install", action: install).buttonStyle(.glassProminent).disabled(typed.isEmpty)
                        .accessibilityIdentifier("plugins.install")
                }
            }
            if let failure = installs.failure {
                NoticeCapsule(tone: .error, text: failure.text) {
                    if let retry = failure.retry {
                        Button("Retry", action: retry).accessibilityIdentifier("notice.retry")
                    }
                }
                .accessibilityIdentifier("plugins.notice")
                .frame(maxWidth: .infinity)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(installs.rows) { PluginRow(row: $0) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Reload Plugins") { Task { await Plugin.reloadAll() } }
                    .buttonStyle(.glass).controlSize(.small).accessibilityIdentifier("plugins.reload-all")
            }
        }
        .font(.system(size: 13))
        .padding(12)
        .frame(width: 480)
        .task { await DefaultPlugins.shared.check() }
        .floatingGlass(in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plugins")
    }

    private func install() {
        let text = source
        Task {
            await PluginInstalls.shared.install(text)
            if PluginInstalls.shared.failure == nil {
                source = ""
            }
        }
    }
}

/// A plugin's icon, name and version, its source, and what it can do here.
private struct PluginRow: View {
    let row: InstalledPlugin
    @Environment(\.look) private var look

    var body: some View {
        let installs = PluginInstalls.shared, id = "plugins.\(row.id)"
        HStack(spacing: 10) {
            ProgramTile(icon: row.manifest?.icon ?? Registry.missing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.manifest?.name.shown ?? row.id).lineLimit(1)
                    Text(row.manifest.map(\.version.shown) ?? "Not installed").foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(id).version")
                }
                Text(row.source).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle).textSelection(.enabled)
                    .accessibilityIdentifier("\(id).source")
            }
            Spacer(minLength: 8)
            if let busy = installs.busy[row.id]
                ?? (DefaultPlugins.shared.installing.contains(row.id) ? "Installing…" : nil)
            {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary).accessibilityIdentifier("\(id).busy")
            } else {
                HStack(spacing: 2) {
                    if row.kind == .bundled {
                        // An edited copy stays the user's until they pick the app's again.
                        let defaults = DefaultPlugins.shared
                        if let version = defaults.newer[row.id] ?? (defaults.edited.contains(row.id) ? "" : nil) {
                            Button(version.isEmpty ? "Reset to Default" : "Update to Version \(version)") {
                                Task { await defaults.put(row.id) }
                            }
                            .buttonStyle(.glass).controlSize(.small).padding(.trailing, 4)
                            .accessibilityIdentifier("\(id).reset")
                        }
                    }
                    if case .installed = row.kind {
                        IconButton(symbol: "arrow.down.circle", help: row.manifest == nil ? "Install" : "Update",
                                   size: 24) { Task { await installs.update(row) } }
                            .accessibilityIdentifier("\(id).update")
                    }
                    if row.manifest != nil {
                        IconButton(symbol: "arrow.clockwise", help: "Reload Plugin", size: 24) {
                            Task { await Plugin.reload(row.id) }
                        }
                        .accessibilityIdentifier("\(id).reload")
                    }
                    if row.kind != .bundled {
                        IconButton(symbol: "trash", help: "Remove", size: 24) { Task { await installs.remove(row) } }
                            .accessibilityIdentifier("\(id).remove")
                    }
                }
                .foregroundStyle(look.paneButton)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}
