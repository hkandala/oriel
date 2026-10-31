import Foundation
import HerdrKit
import SwiftUI

/// The plugins the user trusts, each with the permissions they allowed (future-work/plugins/security#the-trust-prompt),
/// in `trust.json` in the config folder. A plugin asks once before its code first runs, and again only when its
/// permissions grow; the default plugins never ask.
@MainActor @Observable
final class PluginTrust {
    static let shared = PluginTrust()
    private var trusted: [String: [String]]
    private static let file = Registry.config.appending(path: "trust.json")

    private init() {
        trusted = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: Self.file))) ?? [:]
    }

    func allows(_ manifest: PluginManifest) -> Bool {
        Registry.defaults.contains(manifest.id)
            || trusted[manifest.id].map { Set(manifest.permissions).isSubset(of: $0) } == true
    }

    /// Allow: kept, and the plugin's cards waiting on the prompt load.
    func allow(_ manifest: PluginManifest) {
        trusted[manifest.id] = manifest.permissions
        save()
        for card in Plugin.cards where card.manifest == manifest && card.web.bridge?.failure == nil {
            card.web.reload()
        }
    }

    func forget(_ id: String) {
        trusted[id] = nil
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Registry.config, withIntermediateDirectories: true)
        try? JSONEncoder().encode(trusted).write(to: Self.file, options: .atomic)
    }

    /// What it can do, a sentence per permission in the manifest's order; the first says where.
    /// `folder`: the package, whose build script, when it has one, the app runs as the user.
    static func words(_ manifest: PluginManifest, folder: URL?) -> [String] {
        var place = "on the machine of each card you open"
        let words = manifest.permissions.map { permission in
            defer { place = "there" }
            return switch permission {
            case "files:read": "It can read files and folders \(place)."
            case "files:write": "It can change and delete files \(place)."
            case "git": "It can read git repositories \(place), stage, commit, switch branches, pull and push."
            case "run": "It can run any command as you \(place), including ones that use the network or keep running."
            default: "It can write to the clipboard."
            }
        }
        let build = folder.map(PluginPackages.builds) == true
            ? ["Its build script runs as you on this Mac when Oriel builds it."] : []
        return (words.isEmpty ? ["Its page can only draw in its card."] : words) + build
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

/// In the card's middle, before the plugin's code first runs: its id and folder, what it says it is, what it can do,
/// and Don't Allow (closes the pane) or Allow.
struct TrustPrompt: View {
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look

    var body: some View {
        let manifest = plugin.manifest, id = "pane.\(plugin.paneID).trust"
        let folder = Registry.package(manifest.id).map { ($0.path as NSString).abbreviatingWithTildeInPath.shown } ?? ""
        VStack(spacing: 12) {
            Image(systemName: manifest.icon).font(.system(size: 28)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Trust “\(manifest.name.shown)”?").font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier(id)
                Text("\(manifest.id) \(manifest.version.shown) in \(folder)").font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                if !manifest.description.isEmpty {
                    Text(manifest.description.shown).font(.system(size: 12)).lineLimit(3)
                }
                Text(PluginTrust.words(manifest, folder: Registry.package(manifest.id)).joined(separator: " "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary).accessibilityIdentifier("\(id).words")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            HStack(spacing: 8) {
                Button("Don’t Allow") { page.closePane(page.store.pane(plugin.paneID)) }
                    .buttonStyle(.glass).accessibilityIdentifier("\(id).deny")
                Button("Allow") { PluginTrust.shared.allow(manifest) }
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
