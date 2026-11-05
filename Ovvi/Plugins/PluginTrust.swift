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

    /// Remove: its open cards show the confirmation again, and their pages' calls fail (`Bridge.call`) and their
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

    /// Which plugin, and where from: an npm or git source, and its folder (a local path's source).
    static func origin(_ manifest: PluginManifest, source: String, folder: URL?) -> String {
        let folder = folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
        let fetched = PluginSource(source)?.folder != nil ? "from \(source) " : ""
        return "\(manifest.id) \(manifest.version) \(fetched)in \(folder)".shown
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

    var body: some View {
        let manifest = plugin.manifest, id = "pane.\(plugin.paneID).trust"
        let source = PluginInstalls.shared.rows.first { $0.id == manifest.id }?.source ?? ""
        VStack(spacing: 12) {
            Image(symbol: manifest.icon).font(.system(size: 28)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Install “\(manifest.name.shown)”?").font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier(id)
                Text(PluginTrust.origin(manifest, source: source, folder: Registry.package(manifest.id)))
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
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
                    .buttonStyle(.glass).accessibilityIdentifier("\(id).deny")
                Button("Install") { PluginTrust.shared.allow(manifest) }
                    .buttonStyle(.glassProminent).accessibilityIdentifier("\(id).allow")
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(look.cardSolid)
    }
}
