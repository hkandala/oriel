import HerdrKit
import SwiftUI

/// Settings ▸ Plugins (plugins/packages#the-plugins-page): a source to install (`npm:`, `git:` or a folder's path), New
/// Plugin…, Reload All, and every plugin with its icon, name, version and source. A row opens the plugin's page.
struct PluginsPage: View {
    @State private var source = ""

    /// The plugins whose cards wait for the user's answer: the sidebar's badge.
    static var waiting: Int {
        PluginTrust.shared.waiting.count
    }

    /// Each plugin's settings and Show in New Pane, for the sidebar's search.
    static var searchRows: [SettingsSearch] {
        Registry.all.flatMap { manifest in
            let place = "Plugins › \(manifest.name.shown)", detail = SettingsDetail.plugin(manifest.id)
            let rows = manifest.settings.map { setting in
                SettingsSearch(id: PluginPage.row(manifest.id, setting.id), title: setting.title.shown, page: .plugins,
                               words: "\(setting.description ?? "") \(setting.section ?? "")".shown, detail: detail,
                               place: place)
            }
            return rows + (manifest.chooser == nil ? [] : [
                SettingsSearch(id: PluginPage.newPaneRow(manifest.id), title: "Show in New Pane",
                               page: .plugins, words: "chooser", detail: detail, place: place),
            ])
        }
    }

    var body: some View {
        let installs = PluginInstalls.shared, typed = source.trimmingCharacters(in: .whitespaces)
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("Source", text: $source, prompt: Text("npm:package, git:repository or a folder"))
                        .labelsHidden().textFieldStyle(.roundedBorder).onSubmit(install)
                        .accessibilityIdentifier("plugins.source")
                    if let busy = installs.busy[typed] {
                        ProgressView().controlSize(.small)
                        Text(busy).foregroundStyle(.secondary).accessibilityIdentifier("plugins.busy")
                    } else {
                        Button("Install", action: install).buttonStyle(.borderedProminent).disabled(typed.isEmpty)
                            .accessibilityIdentifier("plugins.install")
                    }
                }
            } footer: {
                Text("Ovvi installs with the npm, pnpm or bun in your login shell. It asks before a new plugin runs.")
                    .settingsFooter()
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
            Section {
                PluginLink(row: InstalledPlugin(id: Registry.browser.id, manifest: Registry.browser, kind: .bundled))
                ForEach(installs.rows) { PluginLink(row: $0) }
            } header: {
                HStack {
                    Text("Installed")
                    Spacer()
                    if let busy = installs.busy.first(where: { $0.value == "Creating…" }) {
                        ProgressView().controlSize(.small)
                        Text("Creating \(busy.key)…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button("New Plugin…") { Task { await installs.create() } }.accessibilityIdentifier("plugins.new")
                    Button("Reload All", systemImage: "arrow.clockwise") { Task { await Plugin.reloadAll() } }
                        .accessibilityIdentifier("plugins.reload-all")
                }
                .controlSize(.small)
            }
        }
        .task { await DefaultPlugins.shared.check() }
    }

    private func install() {
        let text = source
        Task {
            _ = try? await PluginInstalls.shared.install(text)
            if PluginInstalls.shared.failure == nil {
                source = ""
            }
        }
    }
}

/// A plugin's row: its icon, name and version, its source, Needs review while its cards wait, and what it is doing.
private struct PluginLink: View {
    let row: InstalledPlugin

    var body: some View {
        let busy = PluginInstalls.shared.busy[row.id]
            ?? (DefaultPlugins.shared.installing.contains(row.id) ? "Installing…" : nil)
        NavigationLink(value: SettingsDetail.plugin(row.id)) {
            HStack(spacing: 10) {
                ProgramTile(icon: row.manifest?.icon ?? Registry.missing)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(row.manifest?.name.shown ?? row.id).lineLimit(1)
                        // The browser is the app's own: no version.
                        if row.manifest?.entry != nil || row.manifest == nil {
                            Text(row.manifest.map(\.version.shown) ?? "Not installed").foregroundStyle(.secondary)
                        }
                    }
                    Text(row.source).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.system(size: 11)).foregroundStyle(.secondary)
                } else if PluginTrust.shared.waiting.contains(row.id) {
                    NeedsReview()
                }
            }
        }
        // One element, whose label reads its texts: "Git, 1.9.0, Comes with Ovvi".
        .accessibilityIdentifier("plugins.\(row.id)")
    }
}

/// "Needs review", an orange capsule: the plugin's cards wait for an answer.
private struct NeedsReview: View {
    @Environment(\.look) private var look

    var body: some View {
        Text("Needs review").font(.system(size: 11, weight: .medium)).foregroundStyle(look.needsYou)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(look.needsYou.opacity(0.15), in: .capsule)
    }
}
