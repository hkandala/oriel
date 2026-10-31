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

    static func url(_ plugin: String, _ page: PluginPage) -> URL {
        URL(string: "\(name)://\(plugin)/")?.appending(path: page.rawValue) ?? URL(filePath: "/")
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let id = url.host(), let manifest = Registry.plugin(id), manifest.id == id,
              let folder = Registry.files(id)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        // One folder, no subfolders: the last component is decoded, so `..%2F` would climb out of it.
        let file = url.lastPathComponent, page = url.pathExtension.isEmpty && PluginPage(rawValue: file) != nil
        // A plugin's entry page runs the app's runtime (`web/oriel`), which imports the entry's build.
        let script = file == PluginPage.main.rawValue ? "oriel" : file
        let css = file == PluginPage.main
            .rawValue ? (((manifest.entry ?? "") as NSString).lastPathComponent as NSString)
            .deletingPathExtension : file
        // A page has its own styles when it imports CSS (esbuild writes `<page>.css`).
        let styles = page && FileManager.default.fileExists(atPath: folder.appending(path: "\(css).css").path)
        // The runtime and the card's base style are the app's, for every plugin.
        let from = ["oriel.js", "card.css"].contains(file) ? Registry.folder : folder
        let data = file.contains("/") || file.hasPrefix(".") ? nil : page ? Data("""
        <!doctype html><meta charset="utf-8"><link rel="stylesheet" href="card.css">\
        \(styles ? "<link rel=\"stylesheet\" href=\"\(css).css\">" : "")\
        <script type="module" src="\(script).js"></script>
        """.utf8) : from.flatMap { try? Data(contentsOf: $0.appending(path: file)) }
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
            "Content-Security-Policy": "default-src 'none'; script-src \(own) 'wasm-unsafe-eval'; "
                + "style-src \(own) 'unsafe-inline'; img-src \(own) data: blob:; media-src blob:; "
                + "font-src \(own) data:; connect-src \(own); frame-src 'none'; form-action 'none'; base-uri 'none'",
        ]) ?? URLResponse())
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
