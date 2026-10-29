import AppKit

// The card draws with SwiftTreeSitter's tree and query types.
@_exported import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// A language the file card colors: its tree-sitter parser and highlight query, by the file's extension.
@MainActor
public struct Grammar {
    public let language: Language
    public let highlights: Query

    // Made once per language, on first use; nil for a file no grammar reads.

    public static func of(_ path: String) -> Grammar? {
        let ext = (path as NSString).pathExtension.lowercased()
        if let made = made[ext] {
            return made
        }
        guard let (parser, queries) = table[ext], let pointer = parser() else { return nil }
        // A TypeScript or C++ query only adds to the JavaScript or C one it extends.
        let source = queries.compactMap { name in
            Bundle.main.url(forResource: "TreeSitter\(name)_TreeSitter\(name)", withExtension: "bundle")
                .flatMap(Bundle.init(url:))?.url(
                    forResource: "highlights",
                    withExtension: "scm",
                    subdirectory: "queries",
                )
                .flatMap { try? Data(contentsOf: $0) }
        }.reduce(Data(), +)
        let language = Language(pointer)
        let grammar = (try? Query(language: language, data: source)).map { Grammar(language: language, highlights: $0) }
        made[ext] = grammar
        return grammar
    }

    private static var made: [String: Grammar?] = [:]

    private static let table: [String: (() -> OpaquePointer?, [String])] = {
        let typescript = ["JavaScript", "TypeScript"], cpp = ["C", "CPP"]
        return [
            "swift": (tree_sitter_swift, ["Swift"]),
            "ts": (tree_sitter_typescript, typescript), "mts": (tree_sitter_typescript, typescript),
            "cts": (tree_sitter_typescript, typescript), "tsx": (tree_sitter_tsx, typescript),
            "js": (tree_sitter_javascript, ["JavaScript"]), "mjs": (tree_sitter_javascript, ["JavaScript"]),
            "cjs": (tree_sitter_javascript, ["JavaScript"]), "jsx": (tree_sitter_javascript, ["JavaScript"]),
            "py": (tree_sitter_python, ["Python"]),
            "go": (tree_sitter_go, ["Go"]),
            "rs": (tree_sitter_rust, ["Rust"]),
            "c": (tree_sitter_c, ["C"]), "h": (tree_sitter_c, ["C"]),
            "cc": (tree_sitter_cpp, cpp), "cpp": (tree_sitter_cpp, cpp), "cxx": (tree_sitter_cpp, cpp),
            "hh": (tree_sitter_cpp, cpp), "hpp": (tree_sitter_cpp, cpp), "hxx": (tree_sitter_cpp, cpp),
            "java": (tree_sitter_java, ["Java"]),
            "kt": (tree_sitter_kotlin, ["Kotlin"]), "kts": (tree_sitter_kotlin, ["Kotlin"]),
            "rb": (tree_sitter_ruby, ["Ruby"]),
            "sh": (tree_sitter_bash, ["Bash"]), "bash": (tree_sitter_bash, ["Bash"]),
            "zsh": (tree_sitter_bash, ["Bash"]),
            "json": (tree_sitter_json, ["JSON"]),
            "yaml": (tree_sitter_yaml, ["YAML"]), "yml": (tree_sitter_yaml, ["YAML"]),
            "toml": (tree_sitter_toml, ["TOML"]),
            "html": (tree_sitter_html, ["HTML"]), "htm": (tree_sitter_html, ["HTML"]),
            "css": (tree_sitter_css, ["CSS"]),
        ]
    }()

    /// A capture's color by the first part of its name, as Xcode's default theme colors those roles.
    public static func color(_ capture: String) -> NSColor? {
        switch capture.prefix(while: { $0 != "." }) {
        case "keyword", "conditional", "repeat", "include", "exception", "storageclass": .systemPink
        case "string", "character": .systemRed
        case "comment": .secondaryLabelColor
        case "number", "float", "boolean", "constant": .systemOrange
        case "type", "constructor", "tag", "namespace", "module": .systemTeal
        case "function", "method": .systemBlue
        case "attribute", "property", "label", "preproc": .systemPurple
        default: nil
        }
    }
}
