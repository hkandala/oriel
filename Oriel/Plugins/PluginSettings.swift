import HerdrKit
import SwiftUI

/// Settings › Plugins (future-work/plugins, decision 5): a source to install (`npm:`, `git:` or a folder's path), and
/// every plugin with its name, version and source, and Update, Reload and Remove.
struct PluginSettings: View {
    private var settings = AppSettings()
    @State private var source = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let installs = PluginInstalls.shared
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Plugins").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Reload Plugins") { Task { await Plugin.reloadAll() } }
                    .buttonStyle(.glass).controlSize(.small).accessibilityIdentifier("plugins.reload-all")
            }
            HStack(spacing: 8) {
                TextField("npm:package, git:repository or a folder", text: $source).focused($focused)
                    .focusSoon($focused).dialogField().onSubmit(install)
                    .accessibilityLabel("Source").accessibilityIdentifier("plugins.source")
                Button("Install", action: install).buttonStyle(.glassProminent)
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty || installs.busy[source] != nil)
                    .accessibilityIdentifier("plugins.install")
            }
            if let failure = installs.failure {
                NoticeCapsule(tone: .error, text: failure.text) {
                    Button("Retry", action: failure.retry).accessibilityIdentifier("notice.retry")
                }
                .accessibilityIdentifier("plugins.notice")
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(installs.rows) { PluginRow(row: $0) }
                }
            }
            .frame(minHeight: 160, maxHeight: 420)
        }
        .font(.system(size: 13))
        .padding(20)
        .frame(width: 540)
        .environment(\.look, look)
        .containerBackground(for: .window) { WindowBackground(look: look) }
        // ⌘W closes it, as About: the menu bar's ⌘W is a main window's Close Pane.
        .background { Button("Close") { dismiss() }.keyboardShortcut("w").opacity(0).accessibilityHidden(true) }
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
            if let busy = installs.busy[row.id] {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary).accessibilityIdentifier("\(id).busy")
            } else {
                HStack(spacing: 2) {
                    if case .installed = row.kind {
                        IconButton(symbol: "arrow.down.circle", help: row.manifest == nil ? "Install" : "Update",
                                   size: 24) { Task { await installs.update(row) } }
                            .accessibilityIdentifier("\(id).update")
                    }
                    if row.kind != .bundled, row.manifest != nil {
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
