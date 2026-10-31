import Foundation
@testable import HerdrKit
import Testing

private func manifest(_ oriel: String, package: String = #""version": "0.1.0""#) throws(ManifestError)
    -> PluginManifest
{
    try PluginManifest(package: Data("{\(package), \"oriel\": {\(oriel)}}".utf8))
}

private let base = #""id": "csv-table", "name": "CSV Table", "api": 1, "entry": "main.ts", "icon": "tablecells""#

private func error(_ oriel: String, package: String = #""version": "0.1.0""#) -> String? {
    do {
        _ = try manifest(oriel, package: package)
        return nil
    } catch {
        return error.text
    }
}

@Test func `a package's oriel key is its manifest, with the package's version and description`() throws {
    let csv = try manifest(base + #""#
        + #", "opens": {"files": ["*.csv", "public.comma-separated-values-text"]}, "permissions": ["files:read"],"#
        + #""header": [{"id": "rows", "type": "text", "style": "dim"}, {"type": "spacer"},"#
        + #"{"id": "first-row", "type": "toggle", "symbol": "tablecells", "title": "First Row", "value": true},"#
        + #"{"id": "mode", "type": "menu", "title": "Mode", "items": [{"value": "a", "title": "A"}, "-"]}],"#
        + #""future": {"ignored": true}"#,
        package: #""name": "@me/csv", "version": "0.1.0", "description": "A table.", "keywords": ["sheet"]"#)
    #expect(csv.id == "csv-table" && csv.version == "0.1.0" && csv.description == "A table." && csv.api == 1)
    #expect(csv.keywords == ["sheet"] && csv.permissions == ["files:read"] && csv.chooser == nil)
    #expect(csv.header.map(\.type) == ["text", "spacer", "toggle", "menu"])
    #expect(csv.header[2].value == .bool(true) && csv.header[3].items?.last?.value == nil)
    #expect(!csv.history)
}

@Test func `the header's app controls, path parts, section headings and item symbols`() throws {
    let tree = try manifest(base + #", "history": true, "header": [{"type": "openWith", "id": "open-with"},"#
        + #"{"id": "jump", "type": "text", "style": "path", "value": ["src", "main.ts"]},"#
        + #"{"id": "root", "type": "menu", "items": [{"title": "Remote"},"#
        + #"{"value": "/", "title": "/", "symbol": "folder"}]}]"#)
    #expect(tree.history && tree.header[0].type == "openWith" && tree.header[1].value == .list(["src", "main.ts"]))
    #expect(tree.header[2].items?.first?.value == nil && tree.header[2].items?.first?.title == "Remote")
    #expect(tree.header[2].items?.last?.symbol == "folder")
    #expect(error(base + #", "header": [{"type": "segmented", "id": "a", "options": [{"title": "A"}]}]"#) != nil)
}

@Test func `a control's value from the page's JSON: a boolean, a list, a string, nothing else`() {
    #expect(PluginManifest.Value(json: true) == .bool(true))
    #expect(PluginManifest.Value(json: 1) == nil)
    #expect(PluginManifest.Value(json: ["a"]) == .list(["a"]))
    #expect(PluginManifest.Value(json: "a") == .text("a"))
    #expect(PluginManifest.Item(json: "-").value == nil && PluginManifest.Item(json: "-").title == nil)
}

@Test func `a bad manifest names its field and what is wrong`() {
    #expect(error(base, package: #""name": "x""#) == "version is missing")
    #expect(error(#""id": "csv""#) == "oriel.name is missing")
    #expect(error(base.replacingOccurrences(of: #""api": 1"#, with: #""api": "1""#)) == "oriel.api has the wrong type")
    #expect(error(base.replacingOccurrences(of: "csv-table", with: "CSV")) != nil)
    #expect(error(base.replacingOccurrences(of: "csv-table", with: "-csv")) != nil)
    #expect(error(base.replacingOccurrences(of: "main.ts", with: "../main.ts")) != nil)
    #expect(error(base.replacingOccurrences(of: "main.ts", with: "main.py")) != nil)
    #expect(error(base + #", "chooser": "CSV", "opens": {"files": ["*.csv"]}"#)
        == "oriel.chooser needs opens with folders or git, or no opens")
    #expect(error(base + #", "header": [{"type": "slider", "id": "a"}]"#) == "oriel.header has an unknown type slider")
    #expect(error(base + #", "header": [{"type": "button", "id": "a"}, {"type": "text", "id": "a"}]"#) != nil)
    #expect(error(base + #", "header": [{"type": "button"}]"#) != nil)
    #expect(error(base + #", "commands": [{"id": "e", "title": "Edit", "key": "e"}]"#) != nil)
    #expect(error(base + #", "permissions": ["network"]"#) == "oriel.permissions has an unknown permission network")
    #expect(error(base + #", "opens": {"priority": "high"}"#) != nil)
    #expect(error(base + #", "header": [{"type": "toggle", "id": "a"}, 5]"#) != nil)
    #expect((try? PluginManifest(package: Data("not json".utf8))) == nil)
    #expect(error(base + #", "chooser": "Notes", "opens": {"folders": true}"#) == nil)
}

@Test func `the most specific pattern wins: a name, an extension, a subtype, its supertype, then anything`() throws {
    func rank(_ files: [String], _ path: String) throws -> Int? {
        let list = files.map { "\"\($0)\"" }.joined(separator: ",")
        return try manifest(base + #", "opens": {"files": [\#(list)]}"#).rank(file: path)
    }
    let name = try #require(try rank(["Makefile"], "/x/Makefile"))
    let ext = try #require(try rank(["*.md"], "/x/README.MD"))
    let text = try #require(try rank(["public.text"], "/x/a.csv"))
    let data = try #require(try rank(["public.data"], "/x/a.csv"))
    let any = try #require(try rank(["*"], "/x/a.csv"))
    #expect(name > ext && ext > text && text > data && data > any)
    #expect(try rank(["*.md"], "/x/a.csv") == nil)
    #expect(try rank(["public.image"], "/x/a.csv") == nil)
    // A name the system does not know matches no type, only a glob.
    #expect(try rank(["public.data"], "/x/main.rs") == nil)
    #expect(try rank(["*.md", "*"], "/x/a.md") == ext)
}
