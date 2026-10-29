// swift-tools-version: 6.2

import PackageDescription

// The file card's syntax colors: tree-sitter and a grammar per language, pinned. Older tags where a newer one's
// manifest drops its scanner (it looks for `src/scanner.c` from the build's folder, not the package's).
// swiftlint:disable:next large_tuple
let grammars: [(url: String, version: Version, product: String)] = [
    ("https://github.com/alex-pinkus/tree-sitter-swift", "0.7.4-with-generated-files", "TreeSitterSwift"),
    ("https://github.com/tree-sitter/tree-sitter-typescript", "0.23.2", "TreeSitterTypeScript"),
    ("https://github.com/tree-sitter/tree-sitter-javascript", "0.23.1", "TreeSitterJavaScript"),
    ("https://github.com/tree-sitter/tree-sitter-python", "0.23.6", "TreeSitterPython"),
    ("https://github.com/tree-sitter/tree-sitter-go", "0.25.0", "TreeSitterGo"),
    ("https://github.com/tree-sitter/tree-sitter-rust", "0.24.2", "TreeSitterRust"),
    ("https://github.com/tree-sitter/tree-sitter-c", "0.24.2", "TreeSitterC"),
    ("https://github.com/tree-sitter/tree-sitter-cpp", "0.23.4", "TreeSitterCPP"),
    ("https://github.com/tree-sitter/tree-sitter-java", "0.23.5", "TreeSitterJava"),
    ("https://github.com/fwcd/tree-sitter-kotlin", "0.3.8", "TreeSitterKotlin"),
    ("https://github.com/tree-sitter/tree-sitter-ruby", "0.23.1", "TreeSitterRuby"),
    ("https://github.com/tree-sitter/tree-sitter-bash", "0.25.1", "TreeSitterBash"),
    ("https://github.com/tree-sitter/tree-sitter-json", "0.24.8", "TreeSitterJSON"),
    ("https://github.com/tree-sitter-grammars/tree-sitter-yaml", "0.7.0", "TreeSitterYAML"),
    ("https://github.com/tree-sitter-grammars/tree-sitter-toml", "0.7.0", "TreeSitterTOML"),
    ("https://github.com/tree-sitter/tree-sitter-html", "0.23.2", "TreeSitterHTML"),
    ("https://github.com/tree-sitter/tree-sitter-css", "0.23.2", "TreeSitterCSS"),
]

let package = Package(
    name: "Grammars",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Grammars", targets: ["Grammars"]),
    ],
    dependencies: [.package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.25.0")]
        + grammars.map { .package(url: $0.url, exact: $0.version) },
    targets: [
        .target(
            name: "Grammars",
            dependencies: [.product(name: "SwiftTreeSitter", package: "swift-tree-sitter")] + grammars.map {
                .product(name: $0.product, package: String($0.url.split(separator: "/").last!))
            },
            swiftSettings: [.treatAllWarnings(as: .error)],
        ),
    ],
)
