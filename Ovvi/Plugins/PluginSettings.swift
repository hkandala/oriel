import HerdrKit
import SwiftUI

/// The plugins' settings (plugins/manifest#settings): one value per setting for all machines, in `settings.json`'s
/// `plugins`, only the values that differ from the default, so a new default reaches whoever never changed it. Read at
/// launch and again with every package (Reload Plugins reads a hand edit); the Settings window writes them and tells
/// the plugin's open cards at once.
@MainActor @Observable
final class PluginSettings {
    static let shared = PluginSettings()
    /// The file's values by plugin and setting id, as last read or written.
    private var saved: [String: [String: PluginSetting.Value]] = [:]

    private init() {
        reload()
    }

    func reload() {
        saved = Dictionary(uniqueKeysWithValues: Registry.all.map { manifest in
            (manifest.id, PluginPackages.values(of: manifest.id, in: Registry.settings)
                .compactMapValues(PluginSetting.Value.init(json:)))
        })
    }

    /// The saved value when it fits the setting, else its default.
    func value(_ setting: PluginSetting, of id: String) -> PluginSetting.Value {
        saved[id]?[setting.id].flatMap { setting.fits($0) ? $0 : nil } ?? setting.default
    }

    /// Every setting's value by id, as JSON: the page's `ovvi.settings`.
    func values(_ manifest: PluginManifest) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.id, value($0, of: manifest.id).json) })
    }

    /// The user's change on the plugin's page: written (the default takes it out), then sent to each of the plugin's
    /// cards in every window, hidden ones too, as its `settings` event.
    func set(_ value: PluginSetting.Value, _ setting: PluginSetting, of id: String) {
        guard setting.fits(value), value != self.value(setting, of: id) else { return }
        let kept = value == setting.default ? nil : value
        do {
            try PluginPackages.store(kept?.json, setting.id, of: id, in: Registry.settings)
        } catch {
            // The Plugins page's notice; the row reads the value kept, so it shows what is saved.
            PluginInstalls.shared.failure = ("Could not save settings.json: \(error.localizedDescription)", nil)
            return
        }
        saved[id, default: [:]][setting.id] = kept
        // ponytail: a page between its context script and its runtime's start misses the event and keeps the old
        // value until it loads again; the runtime would ask for the values once if that bites.
        for card in Plugin.cards where card.manifest.id == id {
            card.web.script()
            card.web.bridge?.event("settings", [setting.id: value.json])
        }
    }
}
