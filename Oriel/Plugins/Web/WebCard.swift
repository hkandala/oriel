import AppKit
import HerdrKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A plugin card's content as a page of the `web/` bundle (`make web`), in a web view of its own: WebKit makes a
/// process per web view whatever the process pool. The page talks to the app through `web/src/lib/bridge.ts`.
@MainActor @Observable
final class WebCard {
    let kind: PluginKind
    /// The page the argument picks.
    var page: PluginPage {
        PluginPage(kind, arg)
    }

    /// The label's argument; a new one (a rename from elsewhere, a diff's source) loads the page again with it.
    var arg: String {
        didSet {
            // Another file: its page reads it again.
            place = nil
            hash = nil
            toast = nil
            if loaded {
                script()
                view.load(URLRequest(url: PluginScheme.url(page)))
            }
        }
    }

    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: WebCardView
    /// A linked open's landing, for the first load only: a line for a file, a path from the repo's root for a diff.
    @ObservationIgnored private var place: String?
    /// Opens a link from the page in a new tab (`Page.open(_:arg:at:from:)`).
    @ObservationIgnored var open: ((PluginKind, String, String?) -> Void)?
    fileprivate(set) var dirty = false
    /// A diff's row 2: Side by Side, and the file list shown. Per card, not saved.
    var split = false {
        didSet { send(["op": "layout", "split": split]) }
    }

    var list = true {
        didSet { send(["op": "list", "open": list]) }
    }

    /// Files: row 2's filter; a page loaded again ends it.
    var filter = ""
    /// Files: the root, when the last `git` ask found it a repository's root; listings then carry git's state.
    @ObservationIgnored var repo: String?
    /// What the Markdown page shows, as it reports it.
    private(set) var markdown = (edit: false, outline: false)
    var toast: Toast?
    /// A File card's jump bar: the scopes around the caret (`file.ts`).
    private(set) var symbol = ""
    /// A PDF preview's `3 of 12`.
    private(set) var pdfPage = ""
    /// The file's hash as last read or saved, which a save checks (`Document.swift`).
    @ObservationIgnored var hash: String?
    /// A save is writing: its own change on disk is no reload.
    @ObservationIgnored var saving = false
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var css = ""

    init(kind: PluginKind, arg: String, place: String?, store: HostStore) {
        self.kind = kind
        self.arg = arg
        self.place = place
        self.store = store
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(PluginScheme.shared, forURLScheme: PluginScheme.name)
        view = WebCardView(frame: .zero, configuration: configuration)
        // The card's fill draws behind the page.
        view.underPageBackgroundColor = .clear
        view.setValue(false, forKey: "drawsBackground")
        view.isInspectable = true
        let relay = Relay(card: self)
        configuration.userContentController.addScriptMessageHandler(relay, contentWorld: .page, name: "oriel")
        view.navigationDelegate = relay
    }

    /// The app's colors as CSS variables. The first call loads the page; the script also starts a page still loading
    /// or loaded again with them, so every first paint has them.
    func theme(_ css: String) {
        self.css = css
        script()
        if loaded {
            view.callAsyncJavaScript("document.documentElement.style.cssText = css", arguments: ["css": css],
                                     in: nil, in: .page)
        } else {
            loaded = true
            view.load(URLRequest(url: PluginScheme.url(page)))
        }
    }

    /// A message to the page's `receive` handler (`web/src/lib/bridge.ts`): row 2's controls. A page reads their first
    /// state from its first ask's reply, so one sent before it listens is no loss.
    func send(_ message: [String: Any]) {
        view.callAsyncJavaScript("window.receive?.(message)", arguments: ["message": message], in: nil, in: .page)
    }

    private func script() {
        var card: [String: Any] = ["arg": arg, "css": css]
        card["at"] = place
        let json = (try? JSONSerialization.data(withJSONObject: card)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
        let content = view.configuration.userContentController
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(
            source: "window.card = \(json); document.documentElement.style.cssText = card.css",
            injectionTime: .atDocumentStart, forMainFrameOnly: true,
        ))
    }

    /// One message from the page: a reply or an error text for an ask, nothing for a report.
    fileprivate func answer(_ body: Any) async -> (Any?, String?) {
        let message = body as? [String: Any] ?? [:]
        switch message["op"] as? String {
        case "read":
            // A page loaded again, maybe for another file: its reports come again.
            dirty = false
            symbol = ""
            pdfPage = ""
            return await read()
        case "save":
            // Only a file read: a nil hash would overwrite whatever is on disk. One save at a time: a second would
            // check the first's old hash; its edits keep the dot for the next ⌘S.
            guard !saving, let text = message["text"] as? String, let hash else { return (nil, "Not read") }
            await save(text, over: hash)
        case "symbol", "page", "dirty", "markdown":
            shows(message)
        case "patch":
            return await patch()
        case "open":
            // No kind: a file, opened with its kind.
            guard let arg = message["arg"] as? String else { return (nil, "No path") }
            open?((message["kind"] as? String).flatMap(PluginKind.init) ?? .explorer, arg, message["at"] as? String)
        default:
            return await files(message)
        }
        return (nil, nil)
    }

    /// A report of what the page shows: the jump bar's symbol, the PDF's page, the dirty dot, Markdown's mode.
    private func shows(_ message: [String: Any]) {
        switch message["op"] as? String {
        case "symbol":
            symbol = message["symbol"] as? String ?? ""
        case "page":
            pdfPage = "\(message["page"] as? Int ?? 1) of \(message["pages"] as? Int ?? 1)"
        case "markdown":
            markdown = (message["edit"] as? Bool == true, message["outline"] as? Bool == true)
        default:
            dirty = message["dirty"] as? Bool == true
        }
    }
}

/// The content controller keeps its handler for good: a strong one kept the card, its web view and its process.
@MainActor
private final class Relay: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    weak var card: WebCard?
    /// The page's process ended since the last load finished: it loads again once.
    private var reloaded = false

    init(card: WebCard) {
        self.card = card
    }

    func userContentController(_: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?)
    {
        await card?.answer(message.body) ?? (nil, "Closed")
    }

    /// The card's own page only: a Markdown file's HTML (a `<meta>` refresh, a form) would take the view, and the
    /// bridge with it, to any site or to another page.
    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let card else { return .cancel }
        return url == PluginScheme.url(card.page) ? .allow : .cancel
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        reloaded = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !reloaded else { return }
        reloaded = true
        card?.dirty = false
        webView.reload()
    }
}

/// Takes the keyboard as a browser's page does.
final class WebCardView: BrowserView {
    /// The ⇧⌘← or ⇧⌘→ the menu handed to the page: WebKit sends it again when the page leaves it, for Move Tab.
    var handed: NSEvent?

    /// WebKit gives the page every ⌘ key first, and CodeMirror takes some of the app's (⌘[ ⌘] select a pane): the
    /// menu goes first, as over a native text view.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        window?.firstResponder === self && NSApp.mainMenu?.performKeyEquivalent(with: event) == true
            || super.performKeyEquivalent(with: event)
    }
}

/// Serves the bundle: `oriel-plugin://app/<page>` is a page that runs `<page>.js`, any other name a file of it.
/// `loadFileURL` runs no module scripts.
@MainActor
final class PluginScheme: NSObject, WKURLSchemeHandler {
    static let shared = PluginScheme()
    static let name = "oriel-plugin"
    private static let folder = Bundle.main.resourceURL?.appending(path: "web")

    static func url(_ page: PluginPage) -> URL {
        URL(string: "\(name)://app/")?.appending(path: page.rawValue) ?? URL(filePath: "/")
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        // One folder, no subfolders: the last component is decoded, so `..%2F` would climb out of it.
        let file = url.lastPathComponent, page = url.pathExtension.isEmpty && PluginPage(rawValue: file) != nil
        // A page has its own styles when it imports CSS (esbuild writes `<page>.css`).
        let styles = page && Self.folder
            .map { FileManager.default.fileExists(atPath: $0.appending(path: "\(file).css").path) } == true
        let data = file.contains("/") || file.hasPrefix(".") ? nil : page ? Data("""
        <!doctype html><meta charset="utf-8"><link rel="stylesheet" href="card.css">\
        \(styles ? "<link rel=\"stylesheet\" href=\"\(file).css\">" : "")\
        <script type="module" src="\(file).js"></script>
        """.utf8) : Self.folder.flatMap { try? Data(contentsOf: $0.appending(path: file)) }
        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        // UTType knows no MIME type for pdf.js's decoders.
        let mime = page ? "text/html" : url.pathExtension == "wasm" ? "application/wasm"
            : UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        // The page's scripts come only from the bundle; a preview shows its file from a blob.
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type": mime,
            "Content-Security-Policy": "default-src \(Self.name):; script-src \(Self.name): 'wasm-unsafe-eval'; "
                + "img-src \(Self.name): data: blob:; media-src blob:; style-src \(Self.name): 'unsafe-inline'",
        ]) ?? URLResponse())
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}

/// A card's page in the card, with the app's colors.
struct WebCardContent: View {
    let card: WebCard
    @Environment(\.self) private var environment
    @Environment(\.look) private var look

    var body: some View {
        let css = [
            ("text", Color.primary), ("dim", look.paneButton), ("divider", look.divider), ("accent", .accentColor),
            ("working", look.working), ("needs-you", look.needsYou), ("finished", look.finished),
            ("error", look.error),
        ].map { name, color in
            let rgb = color.resolve(in: environment)
            return "--\(name): rgb(\(rgb.red * 255) \(rgb.green * 255) \(rgb.blue * 255) / \(rgb.opacity))"
        }.joined(separator: "; ") + "; color-scheme: \(look.dark ? "dark" : "light")"
        WebHost(view: card.view).onChange(of: css, initial: true) { card.theme(css) }
    }
}
