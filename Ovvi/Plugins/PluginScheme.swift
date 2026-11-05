import Foundation
import HerdrKit
import UniformTypeIdentifiers
import WebKit

/// Serves each plugin from its own folder (`Registry.files`): `ovvi-plugin://<id>/<page>` is a page that runs
/// `<page>.js` (the runtime for `main`), any other name a file of it. `loadFileURL` runs no module scripts.
@MainActor
final class PluginScheme: NSObject, WKURLSchemeHandler {
    static let shared = PluginScheme()
    static let name = "ovvi-plugin"

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
        // One folder, no subfolders and no symlinks out of it: the last component is decoded, so `..%2F` would climb
        // out of it.
        let file = url.lastPathComponent, page = file == "main"
        // The page runs the app's runtime (`web/ovvi`), which imports the entry's build: the entry's own script tag
        // fetches it beside the runtime (one module, a module map per page); it has the entry's styles when its build
        // wrote `<entry>.css` beside it (a bundler's CSS of the entry).
        let css = "\(manifest.entryName).css"
        let styles = page && FileManager.default.fileExists(atPath: folder.appending(path: css).path)
        // The runtime and the card's base style are the app's, for every plugin.
        let app = ["ovvi.js", "card.css"].contains(file) ? Registry.folder : nil
        let root = app ?? Registry.package(id), from = app ?? folder
        let data = page ? Data("""
        <!doctype html><meta charset="utf-8"><link rel="stylesheet" href="card.css">\
        \(styles ? "<link rel=\"stylesheet\" href=\"\(css)\">" : "")\
        <script type="module" src="ovvi.js"></script><script type="module" src="\(manifest.entryName).js"></script>
        """.utf8) : root.flatMap { PluginPackages.served(file, in: from, within: $0) }
            .flatMap { try? Data(contentsOf: $0) }
        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        // UTType knows no MIME type for pdf.js's decoders.
        let mime = page ? "text/html" : url.pathExtension == "wasm" ? "application/wasm"
            : UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        // Scripts, styles, fonts and fetches only from the plugin's own folder (plugins/security); a
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
