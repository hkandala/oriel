import Foundation
import HerdrKit
import UniformTypeIdentifiers
import WebKit

/// Serves each plugin from its own folder (`Registry.files`): `oriel-plugin://<id>/<page>` is a page that runs
/// `<page>.js` (the runtime for `main`), any other name a file of it. `loadFileURL` runs no module scripts.
@MainActor
final class PluginScheme: NSObject, WKURLSchemeHandler {
    static let shared = PluginScheme()
    static let name = "oriel-plugin"

    /// A plugin's page: its entry's.
    static func url(_ plugin: String) -> URL {
        URL(string: "\(name)://\(plugin)/main") ?? URL(filePath: "/")
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let id = url.host(), let manifest = Registry.plugin(id), manifest.id == id,
              let folder = Registry.files(id)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        // One folder, no subfolders: the last component is decoded, so `..%2F` would climb out of it.
        let file = url.lastPathComponent, page = file == "main"
        // The page runs the app's runtime (`web/oriel`), which imports the entry's build; it has the entry's styles
        // when the entry imports CSS (esbuild writes `<entry>.css`).
        let css = "\(manifest.entryName).css"
        let styles = page && FileManager.default.fileExists(atPath: folder.appending(path: css).path)
        // The runtime and the card's base style are the app's, for every plugin.
        let from = ["oriel.js", "card.css"].contains(file) ? Registry.folder : folder
        // A file the build lacks from the build before it: the later chunks of a page that kept running over a rebuild.
        let data = file.contains("/") || file.hasPrefix(".") ? nil : page ? Data("""
        <!doctype html><meta charset="utf-8"><link rel="stylesheet" href="card.css">\
        \(styles ? "<link rel=\"stylesheet\" href=\"\(css)\">" : "")\
        <script type="module" src="oriel.js"></script>
        """.utf8) : [from, PluginBuilds.shared.previous[id]].lazy.compactMap(\.self)
            .compactMap { try? Data(contentsOf: $0.appending(path: file)) }.first
        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        // UTType knows no MIME type for pdf.js's decoders.
        let mime = page ? "text/html" : url.pathExtension == "wasm" ? "application/wasm"
            : UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        // Scripts, styles, fonts and fetches only from the plugin's own folder (future-work/plugins/security); a
        // preview shows its file from a blob.
        let own = "\(Self.name)://\(id)"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type": mime,
            // A plugin's build changes under the same names (Reload Plugin): WebKit must not keep the old files.
            "Cache-Control": "no-store",
            "Content-Security-Policy": "default-src 'none'; script-src \(own) 'wasm-unsafe-eval'; "
                + "style-src \(own) 'unsafe-inline'; img-src \(own) data: blob:; media-src blob:; "
                + "font-src \(own) data:; connect-src \(own); frame-src 'none'; form-action 'none'; base-uri 'none'",
        ]) ?? URLResponse())
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
