import HerdrKit
import SwiftUI

/// A plugin card's second header row (future-work/plugins/manifest#header): the manifest's controls, drawn before the
/// page loads, with the page's changes over them (`oriel.controls.set`). Part of the card's native state, so a card
/// loaded again draws the same row.
@MainActor @Observable
final class Header {
    private(set) var controls: [PluginManifest.Control]
    /// A control event for the page: `["id": id, "value": value?, "submit": true?]` (`oriel.on("control")`).
    @ObservationIgnored var send: (([String: Any]) -> Void)?
    /// After any change of a control, the page's or the user's: the state file keeps the values.
    @ObservationIgnored var changed: (() -> Void)?

    init(manifest: PluginManifest) {
        controls = manifest.header
    }

    /// Every control's value by id, as JSON: `oriel.controls.get`'s and the state file's `"controls"`.
    var values: [String: Any] {
        controls.reduce(into: [:]) { values, control in
            if let id = control.id, let value = control.value {
                values[id] = value.json
            }
        }
    }

    /// The values a card had (the state file's `"controls"`): a card made again shows them.
    func restore(_ values: [String: Any]) {
        for (index, control) in controls.enumerated() {
            if let id = control.id, let value = values[id].flatMap(PluginManifest.Value.init(json:)) {
                controls[index].value = value
            }
        }
    }

    /// The page's `oriel.controls.set(id, change)`: value, title, label, symbol, badge, items, hidden, enabled, busy. A
    /// wrong type leaves that field; an unknown id changes nothing.
    func set(_ id: String, _ change: [String: Any]) {
        guard let index = controls.firstIndex(where: { $0.id == id }) else { return }
        var control = controls[index]
        if let value = change["value"].flatMap(PluginManifest.Value.init(json:)) {
            control.value = value
        }
        if let title = change["title"] as? String {
            control.title = title
        }
        if let label = change["label"] as? String {
            control.label = label.isEmpty ? nil : label
        }
        if let symbol = change["symbol"] as? String {
            control.symbol = symbol.isEmpty ? nil : symbol
        }
        if let badge = change["badge"] {
            // A count or a word; 0 and "" clear it.
            let text = (badge as? NSNumber)?.stringValue ?? badge as? String ?? ""
            control.badge = text.isEmpty || text == "0" ? nil : text
        }
        if let items = change["items"] as? [Any] {
            control.items = items.map { PluginManifest.Item(json: $0) }
        }
        for (key, path) in [("hidden", \PluginManifest.Control.hidden), ("enabled", \.enabled), ("busy", \.busy)] {
            if let flag = change[key] as? Bool {
                control[keyPath: path] = flag
            }
        }
        controls[index] = control
        changed?()
    }

    /// A pick, a toggle or a typed character: the control's value changes here first, then the page hears it. A menu's
    /// item may be an action (Choose Folder…): the page sets its value.
    /// Return in a field sends the field's value as it is then.
    func pick(_ id: String, _ value: PluginManifest.Value?, submit: Bool = false) {
        guard let index = controls.firstIndex(where: { $0.id == id }) else { return }
        let control = controls[index], value = submit ? control.value : value
        if let value, control.type != "menu", value != control.value {
            controls[index].value = value
            changed?()
        } else if ["segmented", "field"].contains(control.type), !submit {
            // The same segment again, or a field writing back its text as it loses focus: nothing new for the page.
            return
        }
        var event: [String: Any] = ["id": id]
        event["value"] = value?.json
        if submit {
            event["submit"] = true
        }
        send?(event)
    }
}

extension PluginManifest {
    /// A card's row 2: a header or Back and Forward.
    var hasRow: Bool {
        history || !header.isEmpty
    }
}
