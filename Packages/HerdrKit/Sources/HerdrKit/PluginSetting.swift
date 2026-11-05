import Foundation

/// A value the user sets on the plugin's page in Settings and the plugin's cards read (plugins/manifest#settings): one
/// for all machines.
public struct PluginSetting: Decodable, Sendable, Equatable {
    public let id: String
    /// `toggle`, `choice`, `number`, `text` or `path`.
    public let type: String
    public let title: String
    public let `default`: Value
    /// One line under the title.
    public var description: String?
    /// A heading over this row and the rows after it.
    public var section: String?
    /// A choice's: 2 to 12.
    public var options: [Option]?
    /// A number's range, step and unit (`pt`).
    public var min: Double?, max: Double?, step: Double?
    public var unit: String?
    /// A text's or a path's field when empty.
    public var placeholder: String?
    /// A path's: `file` or `folder`.
    public var kind: String?

    public struct Option: Decodable, Sendable, Equatable {
        public let value: String
        public let title: String

        public init(value: String, title: String) {
            (self.value, self.title) = (value, title)
        }
    }

    /// A toggle's is a boolean, a number's a number, the others' a string.
    public enum Value: Decodable, Sendable, Hashable {
        case bool(Bool), number(Double), text(String)

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let bool = try? value.decode(Bool.self) {
                self = .bool(bool)
            } else if let number = try? value.decode(Double.self) {
                self = .number(number)
            } else {
                self = try .text(value.decode(String.self))
            }
        }

        /// From `settings.json`: a boolean, a number or a string.
        public init?(json: Any) {
            if let number = json as? NSNumber {
                // A JSON boolean is an NSNumber too.
                self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number
                    .doubleValue)
            } else if let text = json as? String {
                self = .text(text)
            } else {
                return nil
            }
        }

        public var json: Any {
            switch self {
            case let .bool(bool): bool
            case let .number(number): number
            case let .text(text): text
            }
        }
    }

    /// A setting the app writes itself (the browser's).
    public init(id: String, type: String, title: String, default value: Value, description: String? = nil,
                options: [Option]? = nil)
    {
        (self.id, self.type, self.title, self.default) = (id, type, title, value)
        (self.description, self.options) = (description, options)
    }

    /// Whether a value fits this setting: its type, a choice's options, a number's range, a text's 1 KB, a path's
    /// start. A value in `settings.json` that does not fit reads as the default.
    public func fits(_ value: Value) -> Bool {
        switch (type, value) {
        case (_, .bool): type == "toggle"
        case let ("choice", .text(text)): options?.contains { $0.value == text } == true
        case let ("number", .number(number)): number.isFinite && number >= min ?? -.infinity
            && number <= max ?? .infinity
        case let ("text", .text(text)): text.utf8.count <= 1024
        case let ("path", .text(text)): text.isEmpty || text.hasPrefix("/") || text == "~" || text.hasPrefix("~/")
        default: false
        }
    }

    /// The rules the types do not carry; `bad` names the field.
    func check(_ bad: (String, String) -> ManifestError) throws(ManifestError) {
        let low = { (char: Character) in char.isASCII && (char.isLowercase || char.isNumber) }
        guard (1 ... 64).contains(id.count), id.first.map(low) == true, id.allSatisfy({ low($0) || $0 == "-" })
        else { throw bad("id", "must be 1 to 64 of a-z, 0-9 and -, starting with a letter or digit") }
        guard ["toggle", "choice", "number", "text", "path"].contains(type) else {
            throw bad("type", "must be toggle, choice, number, text or path")
        }
        let lengths = [("title", title, 1 ... 60), ("section", section ?? "", 0 ... 60),
                       ("description", description ?? "", 0 ... 200)]
        for (field, text, range) in lengths where !range.contains(text.count) {
            throw bad(field, "must be \(range.lowerBound) to \(range.upperBound) characters")
        }
        if type == "choice" {
            let values = Set((options ?? []).map(\.value))
            guard (2 ... 12).contains(options?.count ?? 0), values.count == options?.count,
                  options?.allSatisfy({ !$0.title.isEmpty }) == true
            else { throw bad("options", "must be 2 to 12 options, each with its own value and a title") }
        }
        guard min ?? -.infinity < max ?? .infinity, step ?? 1 > 0 else {
            throw bad("min", "must be under max, and step over 0")
        }
        guard (placeholder ?? "").utf8.count <= 1024 else { throw bad("placeholder", "is over 1 KB") }
        guard kind.map(["file", "folder"].contains) != false else { throw bad("kind", "must be file or folder") }
        guard fits(self.default) else { throw bad("default", "does not fit the type, options or range") }
    }
}

extension PluginManifest {
    /// At most 16 settings, each id once.
    static func check(settings: [PluginSetting], _ bad: (String, String) -> ManifestError) throws(ManifestError) {
        guard settings.count <= 16 else { throw bad("settings", "has over 16 settings") }
        var ids = Set<String>()
        for (index, setting) in settings.enumerated() {
            try setting.check { bad("settings.\(index).\($0)", $1) }
            guard ids.insert(setting.id).inserted else { throw bad("settings.\(index).id", "is taken") }
        }
    }
}
