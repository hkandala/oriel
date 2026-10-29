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
    let kind: String
    let arg: String
    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: WebCardView
    fileprivate(set) var dirty = false
    @ObservationIgnored private var loaded = false

    init(kind: String, arg: String, store: HostStore) {
        self.kind = kind
        self.arg = arg
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
        let card = (try? JSONSerialization.data(withJSONObject: ["arg": arg, "css": css])).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
        let content = view.configuration.userContentController
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(
            source: "window.card = \(card); document.documentElement.style.cssText = card.css",
            injectionTime: .atDocumentStart, forMainFrameOnly: true,
        ))
        if loaded {
            view.callAsyncJavaScript("document.documentElement.style.cssText = css", arguments: ["css": css],
                                     in: nil, in: .page)
        } else {
            loaded = true
            view.load(URLRequest(url: PluginScheme.page(kind)))
        }
    }

    /// One message from the page: a reply or an error text for an ask, nothing for a report.
    fileprivate func answer(_ body: Any) async -> (Any?, String?) {
        let message = body as? [String: Any] ?? [:]
        switch message["op"] as? String {
        case "read":
            guard let path = message["path"] as? String, let store else { return (nil, "No file") }
            do {
                let file = try await Files.read(path, exec: store.machine.exec())
                return (["text": String(decoding: file.data, as: UTF8.self)], nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        case "dirty":
            dirty = message["dirty"] as? Bool == true
        default:
            return (nil, "Unknown message")
        }
        return (nil, nil)
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

/// Serves the bundle: `oriel-plugin://app/<kind>` is a page that runs `<kind>.js`, any other name a file of it.
/// `loadFileURL` runs no module scripts.
@MainActor
final class PluginScheme: NSObject, WKURLSchemeHandler {
    static let shared = PluginScheme()
    static let name = "oriel-plugin"
    private static let folder = Bundle.main.resourceURL?.appending(path: "web")

    static func page(_ kind: String) -> URL {
        URL(string: "\(name)://app/")?.appending(path: kind) ?? URL(filePath: "/")
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        // One folder, no subfolders: the last component is decoded, so `..%2F` would climb out of it.
        let file = url.lastPathComponent, page = url.pathExtension.isEmpty
        let data = file.contains("/") || file.hasPrefix(".") ? nil : page ? Data("""
        <!doctype html><meta charset="utf-8"><link rel="stylesheet" href="card.css">\
        <script type="module" src="\(file).js"></script>
        """.utf8) : Self.folder.flatMap { try? Data(contentsOf: $0.appending(path: file)) }
        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = page ? "text/html"
            : UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        // The page's scripts come only from the bundle.
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type": mime,
            "Content-Security-Policy": "default-src \(Self.name):; img-src \(Self.name): data:; "
                + "style-src \(Self.name): 'unsafe-inline'",
        ]) ?? URLResponse())
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}

/// A card's page in the card, with the app's colors and text size.
struct WebCardContent: View {
    let card: WebCard
    @Environment(\.self) private var environment
    @Environment(\.look) private var look
    @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize

    var body: some View {
        let css = [
            ("text", Color.primary), ("dim", look.paneButton), ("divider", look.divider), ("accent", .accentColor),
            ("working", look.working), ("needs-you", look.needsYou), ("finished", look.finished),
            ("error", look.error),
        ].map { name, color in
            let rgb = color.resolve(in: environment)
            return "--\(name): rgb(\(rgb.red * 255) \(rgb.green * 255) \(rgb.blue * 255) / \(rgb.opacity))"
        }.joined(separator: "; ") + "; --font-size: \(fontSize)px; color-scheme: \(look.dark ? "dark" : "light")"
        WebHost(view: card.view).onChange(of: css, initial: true) { card.theme(css) }
    }
}
