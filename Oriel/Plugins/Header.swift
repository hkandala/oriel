import HerdrKit
import SwiftUI

/// A plugin card's second header row (future-work/plugins/manifest#header): the manifest's controls, drawn before the
/// page loads, with the page's changes over them (`oriel.controls.set`). Part of the card's native state, so a card
/// loaded again draws the same row.
@MainActor @Observable
final class Header {
    private(set) var controls: [PluginManifest.Control]
    /// Back and Forward at the row's left.
    let history: Bool
    /// A control event for the page: `["id": id, "value": value?, "submit": true?]` (`oriel.on("control")`).
    @ObservationIgnored var send: (([String: Any]) -> Void)?
    /// After any change of a control, the page's or the user's: the state file keeps the values.
    @ObservationIgnored var changed: (() -> Void)?

    init(manifest: PluginManifest) {
        controls = manifest.header
        history = manifest.history
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
            if let id = control.id, let value = values[id].flatMap(PluginManifest.Value.init) {
                controls[index].value = value
            }
        }
    }

    /// The page's `oriel.controls.set(id, change)`: value, title, symbol, badge, items, hidden, enabled, busy. A wrong
    /// type leaves that field; an unknown id changes nothing.
    func set(_ id: String, _ change: [String: Any]) {
        guard let index = controls.firstIndex(where: { $0.id == id }) else { return }
        var control = controls[index]
        if let value = change["value"].flatMap(PluginManifest.Value.init) {
            control.value = value
        }
        if let title = change["title"] as? String {
            control.title = title
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
            control.items = items.map(PluginManifest.Item.init)
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
    func pick(_ id: String, _ value: PluginManifest.Value?, submit: Bool = false) {
        if let value, let index = controls.firstIndex(where: { $0.id == id }), controls[index].type != "menu",
           controls[index].value != value
        {
            controls[index].value = value
            changed?()
        }
        var event: [String: Any] = ["id": id]
        event["value"] = value?.json
        if submit {
            event["submit"] = true
        }
        send?(event)
    }
}

extension PluginManifest.Value {
    /// From the page's JSON: a boolean, a list of strings or a string.
    init?(_ json: Any) {
        // A JSON number is an NSNumber too: only a real boolean is one.
        if let number = json as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            self = .bool(number.boolValue)
        } else if let list = json as? [String] {
            self = .list(list)
        } else if let text = json as? String {
            self = .text(text)
        } else {
            return nil
        }
    }

    var json: Any {
        switch self {
        case let .bool(bool): bool
        case let .text(text): text
        case let .list(list): list
        }
    }

    var text: String? {
        if case let .text(text) = self {
            text
        } else {
            nil
        }
    }
}

extension PluginManifest.Item {
    /// From the page's JSON: `{ value, title, symbol }`, `{ title }` (a section heading) or `"-"` (a divider).
    init(_ json: Any) {
        let item = json as? [String: Any] ?? [:]
        self.init(value: item["value"] as? String, title: item["title"] as? String, symbol: item["symbol"] as? String)
    }
}
