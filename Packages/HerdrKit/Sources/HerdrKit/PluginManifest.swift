import Foundation
import UniformTypeIdentifiers

/// A plugin's manifest (plugins/manifest): the `oriel` key of its package's `package.json`, with the
/// package's `version`, `description` and `keywords`. Read before any of the plugin's code runs, so the chooser, ⌘K
/// and Open With list it at once. Unknown fields are ignored, so a manifest written for a newer app still loads.
public struct PluginManifest: Decodable, Sendable, Equatable {
    public let id: String
    /// What the user reads: the tab's first part, the placeholder's title, Open With, ⌘K.
    public let name: String
    public let version: String
    /// The API version it is written for.
    public let api: Int
    /// The entry file, relative to the package; nil only for a kind the app draws itself (the browser).
    public let entry: String?
    /// An SF Symbol: the card's, the tab's and the chooser's icon.
    public let icon: String
    /// One line: the chooser row's detail.
    public let description: String
    /// More words ⌘K finds its Open ‹chooser› Here by.
    public let keywords: [String]
    public let opens: Opens
    /// The chooser row's title, and the command Open ‹chooser› Here.
    public let chooser: String?
    public let header: [Control]
    /// Back and Forward at the left of the header, over the places the card went to (`card.go`).
    public let history: Bool
    public let commands: [Command]
    /// The app's commands the card takes: `save`, `find`.
    public let handles: [String]
    public let permissions: [String]

    public struct Opens: Decodable, Sendable, Equatable {
        /// Name globs (`*.csv`, `Makefile`) and uniform type identifiers (`public.image`).
        public var files: [String] = []
        /// A folder: the root of its git repository, else the folder.
        public var folders = false
        /// A repository's root, then `uncommitted` or a commit hash.
        public var git = false
        public var urls: [String] = []
        /// `option`: only from Open With, never a file's default.
        public var priority = "default"

        public init(files: [String] = [], folders: Bool = false, git: Bool = false, urls: [String] = []) {
            self.files = files
            self.folders = folders
            self.git = git
            self.urls = urls
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: OpensKeys.self)
            files = try values.decodeIfPresent([String].self, forKey: .files) ?? []
            folders = try values.decodeIfPresent(Bool.self, forKey: .folders) ?? false
            git = try values.decodeIfPresent(Bool.self, forKey: .git) ?? false
            urls = try values.decodeIfPresent([String].self, forKey: .urls) ?? []
            priority = try values.decodeIfPresent(String.self, forKey: .priority) ?? "default"
        }
    }

    /// A control of the card's second header row. Its fields are vars: the page changes them (`controls.set`).
    public struct Control: Decodable, Sendable, Equatable {
        public let type: String
        public let id: String?
        public var symbol: String?
        public var title: String?
        /// What VoiceOver reads, when the title (with a button's badge) says too little: "Push, 1 ahead".
        public var label: String?
        /// An `openWith`'s is the file's path.
        public var value: Value?
        /// A segmented control's.
        public var options: [Item]?
        /// A menu's; `"-"` is a divider.
        public var items: [Item]?
        public var placeholder: String?
        /// A text's: `plain`, `dim` or `path`.
        public var style: String?
        /// A text's `mono`: monospaced digits, so a count (`3 of 12`) keeps its width as it changes.
        public var digits: String?
        /// The points before the control: 6 by default; 0 joins icon buttons into a group (zoom), 2 sets them close.
        public var gap: Double?
        public var hidden: Bool?
        public var enabled: Bool?
        /// A button's count after its symbol (Git's commits ahead).
        public var badge: String?
        /// A spinner in place of a button's or a menu's symbol while its work runs.
        public var busy: Bool?
    }

    /// A toggle's value is a boolean, a path text's a list of parts, the others' a string.
    public enum Value: Decodable, Sendable, Equatable {
        case bool(Bool), text(String), list([String])

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let bool = try? value.decode(Bool.self) {
                self = .bool(bool)
            } else if let list = try? value.decode([String].self) {
                self = .list(list)
            } else {
                self = try .text(value.decode(String.self))
            }
        }
    }

    /// A segmented control's option or a menu's item; a divider has neither value nor title, a menu's section heading
    /// only a title.
    public struct Item: Decodable, Sendable, Equatable {
        public let value: String?
        public let title: String?
        public let symbol: String?

        public init(value: String?, title: String?, symbol: String? = nil) {
            (self.value, self.title, self.symbol) = (value, title, symbol)
        }

        public init(from decoder: any Decoder) throws {
            if let divider = try? decoder.singleValueContainer().decode(String.self), divider == "-" {
                (value, title, symbol) = (nil, nil, nil)
                return
            }
            let values = try decoder.container(keyedBy: ItemKeys.self)
            value = try values.decodeIfPresent(String.self, forKey: .value)
            title = try values.decode(String.self, forKey: .title)
            symbol = try values.decodeIfPresent(String.self, forKey: .symbol)
        }
    }

    /// A menu bar and ⌘K command of the card while it has the keyboard.
    public struct Command: Decodable, Sendable, Equatable {
        public let id: String
        public let title: String
        /// `file`, `edit` or `view`.
        public let menu: String?
        /// A ⌘ chord: `cmd+e`, `cmd+shift+k`.
        public let key: String?
        public let symbol: String?
        public let checked: Bool?
    }

    /// A kind the app writes itself (the browser): no entry, header, commands or permissions.
    public init(id: String, name: String, icon: String, description: String, keywords: [String], opens: Opens,
                chooser: String?)
    {
        (self.id, self.name, version, api, entry, self.icon) = (id, name, "1.0.0", 1, nil, icon)
        (self.description, self.keywords, self.opens, self.chooser) = (description, keywords, opens, chooser)
        (header, history, commands, handles, permissions) = ([], false, [], [], [])
    }

    /// The built entry's file name without `.js`: the runtime imports it, and its CSS shares the name.
    public var entryName: String {
        (((entry ?? "") as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// A package's `package.json`; a missing field or a wrong value throws the field's name and what is wrong.
    public init(package data: Data) throws(ManifestError) {
        do {
            self = try JSONDecoder().decode(Self.self, from: data)
        } catch let error as ManifestError {
            throw error
        } catch let DecodingError.keyNotFound(key, context) {
            throw ManifestError(field: context.codingPath + [key], "is missing")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw ManifestError(field: context.codingPath, "has the wrong type")
        } catch let DecodingError.dataCorrupted(context) where !context.codingPath.isEmpty {
            throw ManifestError(field: context.codingPath, "has the wrong type")
        } catch {
            throw ManifestError(text: "is not JSON")
        }
    }

    public init(from decoder: any Decoder) throws {
        let package = try decoder.container(keyedBy: PackageKeys.self)
        version = try package.decode(String.self, forKey: .version)
        description = try package.decodeIfPresent(String.self, forKey: .description) ?? ""
        keywords = try package.decodeIfPresent([String].self, forKey: .keywords) ?? []
        let values = try package.nestedContainer(keyedBy: Keys.self, forKey: .oriel)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        api = try values.decode(Int.self, forKey: .api)
        entry = try values.decode(String.self, forKey: .entry)
        icon = try values.decode(String.self, forKey: .icon)
        opens = try values.decodeIfPresent(Opens.self, forKey: .opens) ?? Opens()
        chooser = try values.decodeIfPresent(String.self, forKey: .chooser)
        header = try values.decodeIfPresent([Control].self, forKey: .header) ?? []
        history = try values.decodeIfPresent(Bool.self, forKey: .history) ?? false
        commands = try values.decodeIfPresent([Command].self, forKey: .commands) ?? []
        handles = try values.decodeIfPresent([String].self, forKey: .handles) ?? []
        permissions = try values.decodeIfPresent([String].self, forKey: .permissions) ?? []
        try check(values.codingPath)
    }

    private enum PackageKeys: String, CodingKey {
        case version, description, keywords, oriel
    }

    private enum Keys: String, CodingKey {
        case id, name, api, entry, icon, opens, chooser, header, history, commands, handles, permissions
    }

    /// The manifest page's rules the types do not carry.
    private func check(_ path: [any CodingKey]) throws {
        func bad(_ field: String, _ text: String) -> ManifestError {
            ManifestError(text: (path.map(\.stringValue) + [field]).joined(separator: ".") + " " + text)
        }
        let low = { (char: Character) in char.isASCII && (char.isLowercase || char.isNumber) }
        guard (1 ... 64).contains(id.count), id.first.map(low) == true, id.allSatisfy({ low($0) || $0 == "-" })
        else { throw bad("id", "must be 1 to 64 of a-z, 0-9 and -, starting with a letter or digit") }
        guard !name.isEmpty, !icon.isEmpty else { throw bad(name.isEmpty ? "name" : "icon", "is empty") }
        guard api >= 1 else { throw bad("api", "must be 1 or more") }
        let file = entry ?? ""
        // The package's build writes it (`dist/main.js`); the page loads it with its chunks and CSS from its folder.
        guard (file as NSString).pathExtension == "js", !file.hasPrefix("/"), !file.split(separator: "/").contains("..")
        else { throw bad("entry", "must be a built .js file in the package") }
        guard ["default", "option"].contains(opens.priority) else {
            throw bad("opens.priority", "must be default or option")
        }
        // A file or an address needs a path the chooser has not got.
        guard chooser == nil || opens.files.isEmpty && opens.urls.isEmpty || opens.folders || opens.git else {
            throw bad("chooser", "needs opens with folders or git, or no opens")
        }
        try checkControls(bad)
    }

    private func checkControls(_ bad: (String, String) -> ManifestError) throws {
        let controls = ["button", "toggle", "segmented", "menu", "field", "text", "spacer", "openWith"]
        var ids = Set<String>()
        for control in header {
            guard controls.contains(control.type) else { throw bad("header", "has an unknown type \(control.type)") }
            guard control.type == "spacer" || control.id.map({ ids.insert($0).inserted }) == true else {
                throw bad("header", "needs a unique id on each \(control.type)")
            }
            // A segmented option without a value would show as picked while nothing is.
            guard control.gap ?? 0 >= 0, control.digits ?? "mono" == "mono",
                  control.options?.allSatisfy({ $0.value != nil }) != false
            else {
                throw bad("header", "has a bad gap, digits or option on \(control.id ?? "")")
            }
        }
        for command in commands {
            guard ids.insert(command.id).inserted else { throw bad("commands", "has the id \(command.id) twice") }
            guard command.menu.map(["file", "edit", "view"].contains) != false else {
                throw bad("commands", "menu must be file, edit or view")
            }
            guard command.key.map({ $0.hasPrefix("cmd+") && $0.count > 4 }) != false else {
                throw bad("commands", "key must be a ⌘ chord such as cmd+e")
            }
        }
        if let handle = handles.first(where: { !["save", "find"].contains($0) }) {
            throw bad("handles", "has an unknown command \(handle)")
        }
        let known = ["files:read", "files:write", "git", "run", "clipboard"]
        if let permission = permissions.first(where: { !known.contains($0) }) {
            throw bad("permissions", "has an unknown permission \(permission)")
        }
    }

    /// How well a file's name matches `opens.files`: the higher, the more specific; nil when it does not. An exact
    /// name, then an extension glob, then a type (a subtype before its supertype), then `*`. By the name alone, so a
    /// remote file is not read first. A name the system does not know (`.rs`) matches no type.
    public func rank(file path: String) -> Int? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let type = ext.isEmpty ? nil : UTType(filenameExtension: ext).flatMap { $0.isDynamic ? nil : $0 }
        return opens.files.compactMap { pattern -> Int? in
            if pattern == "*" {
                return 0
            }
            if !pattern.contains("*"), let wanted = UTType(pattern) {
                // More supertypes: a more specific type.
                return type?.conforms(to: wanted) == true ? 100 + wanted.supertypes.count : nil
            }
            guard fnmatch(pattern, name, FNM_CASEFOLD) == 0 else { return nil }
            return pattern.contains(where: { "*?[".contains($0) }) ? 900 : 1000
        }.max()
    }
}

private enum OpensKeys: String, CodingKey {
    case files, folders, git, urls, priority
}

private enum ItemKeys: String, CodingKey {
    case value, title, symbol
}

/// A bad manifest: the field and what is wrong (`oriel.id is missing`).
public struct ManifestError: Error, Equatable, CustomStringConvertible {
    public let text: String

    init(text: String) {
        self.text = text
    }

    init(field path: [any CodingKey], _ text: String) {
        // An array's index reads `header.1`.
        self.text = path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") + " " + text
    }

    public var description: String {
        text
    }
}

public extension PluginManifest.Value {
    /// From the page's JSON: a boolean, a list of strings or a string.
    init?(json: Any) {
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

public extension PluginManifest.Item {
    /// From the page's JSON: `{ value, title, symbol }`, `{ title }` (a section heading) or `"-"` (a divider).
    init(json: Any) {
        let item = json as? [String: Any] ?? [:]
        self.init(value: item["value"] as? String, title: item["title"] as? String, symbol: item["symbol"] as? String)
    }
}
