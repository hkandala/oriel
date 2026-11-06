import Foundation
import HerdrKit
import SwiftUI

/// The plugins the user confirmed (plugins/security#the-confirmation), by id in `trust.json` in the config folder. A
/// plugin asks once before its code first runs; the default plugins never ask.
@MainActor @Observable
final class PluginTrust {
    static let shared = PluginTrust()
    private var trusted: Set<String>
    private static let file = Registry.config.appending(path: "trust.json")

    /// What the confirmation says, at install and in a card.
    static let warning = "Plugins run code as you on this Mac and on the machines whose cards you open, including "
        + "their build script. Install plugins only from sources you trust."

    private init() {
        let data = (try? Data(contentsOf: Self.file)) ?? Data()
        // An older Ovvi kept each id with its permissions: those ids count as confirmed.
        trusted = Set((try? JSONDecoder().decode([String].self, from: data))
            ?? (try? JSONDecoder().decode([String: [String]].self, from: data))?.keys.map(\.self) ?? [])
    }

    func allows(_ manifest: PluginManifest) -> Bool {
        Registry.defaults.contains(manifest.id) || trusted.contains(manifest.id)
    }

    /// Install: kept, and the plugin's cards waiting on the confirmation load.
    func allow(_ manifest: PluginManifest) {
        trusted.insert(manifest.id)
        save()
        for card in Plugin.cards where card.manifest == manifest && card.web.bridge?.failure == nil {
            card.web.reload()
        }
    }

    /// Remove: a page still running (its card shows the plugin missing) can call nothing more (`Bridge.call`), and its
    /// watches stop.
    func forget(_ id: String) {
        trusted.remove(id)
        save()
        for card in Plugin.cards where card.manifest.id == id {
            card.web.bridge?.reset()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Registry.config, withIntermediateDirectories: true)
        try? JSONEncoder().encode(trusted.sorted()).write(to: Self.file, options: .atomic)
    }

    /// Which plugin, and where from: its npm or git source, if it has one, and its folder.
    static func origin(_ manifest: PluginManifest, source: String?, folder: URL?) -> String {
        let folder = folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
        return "\(manifest.id) \(manifest.version) \(source.map { "from \($0) " } ?? "")in \(folder)".shown
    }
}

extension String {
    /// Text from a manifest, without control or direction-override characters: a plugin picks its own words.
    var shown: String {
        String(String.UnicodeScalarView(unicodeScalars.filter {
            ![.control, .format].contains($0.properties.generalCategory)
        }))
    }
}

/// In the card's middle, before the plugin's code first runs: which plugin and where from, what it says it is, the
/// warning, and Cancel (closes the pane) or Install.
struct TrustPrompt: View {
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look
    @Environment(\.litCard) private var lit

    var body: some View {
        let manifest = plugin.manifest, id = "pane.\(plugin.paneID).trust"
        let folder = Registry.package(manifest.id)
        // The npm or git source installed into its folder; a local path or a hand-made folder has none.
        let name = folder?.lastPathComponent
        let source = PluginPackages.sources(Registry.settings).first { name != nil && PluginSource($0)?.folder == name }
        VStack(spacing: 12) {
            Image(symbol: manifest.icon).font(.system(size: 28)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Install “\(manifest.name.shown)”?").font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier(id)
                Text(PluginTrust.origin(manifest, source: source, folder: folder))
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    .accessibilityIdentifier("\(id).origin")
                if !manifest.description.isEmpty {
                    Text(manifest.description.shown).font(.system(size: 12)).lineLimit(3)
                }
                Text(PluginTrust.warning).font(.system(size: 12))
                    .foregroundStyle(.secondary).accessibilityIdentifier("\(id).words")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            if manifest.chooser != nil {
                NewPaneSwitch(manifest: manifest).toggleStyle(.checkbox).font(.system(size: 11))
                    .foregroundStyle(.secondary).accessibilityIdentifier("\(id).new-pane")
            }
            HStack(spacing: 8) {
                Button("Cancel") { page.closePane(page.store.pane(plugin.paneID)) }
                    .buttonStyle(.glass).accessibilityIdentifier("\(id).cancel")
                Button("Install") { PluginTrust.shared.allow(manifest) }
                    .buttonStyle(.glassProminent).accessibilityIdentifier("\(id).install")
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(look.cardSolid(keyboard: lit))
    }
}
