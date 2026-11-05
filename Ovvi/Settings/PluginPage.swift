import HerdrKit
import SwiftUI

/// A plugin's page under Settings ▸ Plugins (plugins/packages#a-plugins-page): its header with what it can do here, its
/// settings drawn from its manifest, and Show in New Pane.
struct PluginPage: View {
    let id: String
    @Environment(\.dismiss) private var dismiss

    /// A search row's id, and the row it rings.
    static func row(_ plugin: String, _ setting: String) -> String {
        "plugin.\(plugin).\(setting)"
    }

    /// Show in New Pane's: `+` is in no setting's id.
    static func newPaneRow(_ plugin: String) -> String {
        "plugin.\(plugin).+new-pane"
    }

    var body: some View {
        let row = id == Registry.browser.id ? InstalledPlugin(id: id, manifest: Registry.browser, kind: .bundled)
            : PluginInstalls.shared.rows.first { $0.id == id }
        Form {
            if let failure = PluginInstalls.shared.failure {
                NoticeCapsule(tone: .error, text: failure.text) {}.frame(maxWidth: .infinity)
                    .accessibilityIdentifier("plugins.notice")
            }
            if let row {
                Section { PluginSummary(row: row, gone: { dismiss() }) }
                if let manifest = row.manifest {
                    let sections = Self.sections(manifest.settings)
                    ForEach(sections, id: \.offset) { index, section in
                        Section {
                            ForEach(section.settings, id: \.id) { SettingRow(setting: $0, plugin: id) }
                            // The last section ends with the rows of Ovvi's own, as one card.
                            if index == sections.count - 1 {
                                inOvvi(manifest)
                            }
                        } header: {
                            Text(section.title)
                        } footer: {
                            // A card's own choices are the default plugins' way; another plugin may read them live.
                            if Registry.defaults.contains(id), index == sections.count - 1 {
                                Text("New cards start with the settings above. A card keeps its own choice once you "
                                    + "change it in its header.").settingsFooter()
                            }
                        }
                    }
                    if sections.isEmpty, manifest.chooser != nil {
                        Section { inOvvi(manifest) }
                    }
                }
                if row.kind != .bundled {
                    PluginRemove(row: row, gone: { dismiss() })
                }
            }
        }
        // A pushed page takes no style from the stack it is pushed on.
        .formStyle(.grouped)
        .navigationTitle(row?.manifest?.name.shown ?? id)
        .scrollsToRing()
    }

    /// Show in New Pane, and the browser's link to its approved websites.
    @ViewBuilder
    private func inOvvi(_ manifest: PluginManifest) -> some View {
        if manifest.chooser != nil {
            NewPaneSwitch(manifest: manifest).accessibilityIdentifier("plugins.\(id).new-pane")
                .settingsRow(Self.newPaneRow(id))
        }
        if id == Registry.browser.id, PrivacyPage.hasItems {
            LabeledContent("Approved websites") {
                Button("Show in Privacy") { SettingsRoute.shared.open(.privacy) }
                    .accessibilityIdentifier("plugins.browser.privacy")
            }
        }
    }

    /// The settings in groups: a setting with a `section` starts one under that heading.
    private static func sections(_ settings: [PluginSetting])
        -> [(offset: Int, element: (title: String, settings: [PluginSetting]))]
    {
        let groups = settings.reduce(into: [(title: String, settings: [PluginSetting])]()) { groups, setting in
            if let title = setting.section ?? (groups.isEmpty ? "Settings" : nil) {
                groups.append((title.shown, [setting]))
            } else {
                groups[groups.count - 1].settings.append(setting)
            }
        }
        return Array(groups.enumerated())
    }
}

/// The header: icon, name and version, description and source, and Update, Reset to Default or Update to Version, Show
/// Log and Reload as each applies (Remove is at the bottom of the page).
private struct PluginSummary: View {
    let row: InstalledPlugin
    /// Its row went: installed under its manifest's id.
    let gone: () -> Void

    var body: some View {
        let installs = PluginInstalls.shared, defaults = DefaultPlugins.shared, id = "plugins.\(row.id)"
        let manifest = row.manifest, busy = installs.busy[row.id]
            ?? (defaults.installing.contains(row.id) ? "Installing…" : nil)
        // The browser is the app's own: no version.
        let version = manifest?.entry != nil || manifest == nil ? manifest.map(\.version.shown) ?? "Not installed" : nil
        let lines = [manifest?.description.shown ?? "", row.source]
        SettingsHeader(title: manifest?.name.shown ?? row.id, note: version, lines: lines) {
            ProgramTile(icon: manifest?.icon ?? Registry.missing).scaleEffect(2)
        } actions: {
            if let busy {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary).accessibilityIdentifier("\(id).busy")
            } else {
                if case .installed = row.kind {
                    Button(manifest == nil ? "Install" : "Update") {
                        Task {
                            await installs.update(row)
                            if !installs.rows.contains(where: { $0.id == row.id }) {
                                gone()
                            }
                        }
                    }
                    .accessibilityIdentifier("\(id).update")
                }
                if row.kind == .bundled, let offer = defaults.offers[row.id] {
                    // An edited copy stays the user's until they pick the app's again.
                    Button(offer.map { "Update to Version \($0)" } ?? "Reset to Default") {
                        Task { await defaults.reset(row.id) }
                    }
                    .accessibilityIdentifier("\(id).reset")
                }
                if manifest?.entry != nil {
                    Button("Show Log") { PluginLog.show(row.id) }.accessibilityIdentifier("\(id).log")
                    Button("Reload") { Task { await Plugin.reload(row.id) } }.accessibilityIdentifier("\(id).reload")
                }
            }
        }
    }
}

/// Remove, at the bottom of a page of a plugin that is not the app's own.
private struct PluginRemove: View {
    let row: InstalledPlugin
    let gone: () -> Void

    var body: some View {
        let installs = PluginInstalls.shared
        Section {
            LabeledContent {
                Button("Remove…", role: .destructive) {
                    Task {
                        await installs.remove(row)
                        if !installs.rows.contains(where: { $0.id == row.id }) {
                            gone()
                        }
                    }
                }
                .disabled(installs.busy[row.id] != nil)
                .accessibilityIdentifier("plugins.\(row.id).remove")
            } label: {
                Text("Remove \((row.manifest?.name ?? row.id).shown)")
                Text(PluginInstalls.removal(row))
            }
        }
    }
}

/// A setting drawn by its type: a switch, a segmented control for up to 4 short options or a pop-up menu, a number
/// field with a stepper held in the range, a text or path field saved on Return or when it loses the keyboard.
private struct SettingRow: View {
    let setting: PluginSetting
    let plugin: String
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        let store = PluginSettings.shared, value = store.value(setting, of: plugin)
        let set = { (value: PluginSetting.Value) in store.set(value, setting, of: plugin) }
        Group {
            switch (setting.type, value) {
            case let ("toggle", .bool(isOn)):
                Toggle(isOn: Binding { isOn } set: { set(.bool($0)) }) { label }
            case ("choice", _):
                let options = setting.options ?? []
                let picker = Picker(selection: Binding { value } set: { set($0) }) {
                    ForEach(options, id: \.value) {
                        Text($0.title.shown).tag(PluginSetting.Value.text($0.value))
                    }
                } label: { label }
                // Short: they fit beside the title, as Git's Unified | Side by Side.
                if options.count <= 4, options.map(\.title.count).reduce(0, +) <= 24 {
                    picker.pickerStyle(.segmented)
                } else {
                    picker
                }
            case let ("number", .number(number)):
                let range = (setting.min ?? -1e9) ... (setting.max ?? 1e9)
                LabeledContent {
                    HStack(spacing: 4) {
                        TextField("", value: Binding { number } set: { set(.number(min(max($0, range.lowerBound),
                                                                                       range.upperBound))) },
                        format: .number)
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 70)
                        if let unit = setting.unit {
                            Text(unit.shown).foregroundStyle(.secondary)
                        }
                        Stepper("", value: Binding { number } set: { set(.number($0)) }, in: range,
                                step: setting.step ?? 1).labelsHidden()
                    }
                } label: { label }
            case let (_, .text(text)):
                LabeledContent {
                    TextField(setting.title.shown, text: Binding { draft ?? text } set: { draft = $0 },
                              prompt: Text((setting.placeholder ?? (setting.type == "path"
                                      ? "A \(setting.kind ?? "file")’s path" : "")).shown))
                        .labelsHidden().multilineTextAlignment(.trailing).truncationMode(.middle).frame(width: 220)
                        .focused($focused)
                        .onSubmit { save() }
                        .onChange(of: focused) {
                            if !focused {
                                save()
                            }
                        }
                } label: { label }
            default:
                EmptyView()
            }
        }
        .accessibilityIdentifier("plugins.\(plugin).setting.\(setting.id)")
        .settingsRow(PluginPage.row(plugin, setting.id))
    }

    @ViewBuilder
    private var label: some View {
        Text(setting.title.shown)
        if let description = setting.description {
            Text(description.shown)
        }
    }

    /// The text typed, if it fits (a path starts with / or ~); the field shows the saved value again either way.
    private func save() {
        if let draft {
            PluginSettings.shared.set(.text(draft), setting, of: plugin)
        }
        draft = nil
    }
}

/// Whether the New Pane chooser shows a plugin's row, in `settings.json`.
struct NewPaneSwitch: View {
    let manifest: PluginManifest

    var body: some View {
        Toggle("Show in New Pane", isOn: Binding { Registry.inNewPane(manifest) } set: {
            Registry.show(manifest.id, inNewPane: $0)
        })
    }
}
