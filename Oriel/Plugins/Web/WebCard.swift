import AppKit
import HerdrKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A plugin card's content as a page of its plugin's folder (`make web`), in a web view of its own: WebKit makes a
/// process per web view whatever the process pool. File Explorer's and Git's pages talk to the app through
/// `web/src/lib/bridge.ts`; a plugin's entry page (`main`) through the plugin API (`Bridge`).
@MainActor @Observable
final class WebCard {
    /// Its plugin's id: File Explorer's or Git's.
    let plugin: String
    /// The page the argument picks.
    private(set) var page: PluginPage

    /// The place shown: a file's or a folder's path, a diff's root and source. The label follows it (`Plugin.show`).
    private(set) var arg: String

    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: WebCardView
    /// A `main` page's calls and events.
    var bridge: Bridge?
    /// A linked open's landing, for the first load only: a line for a file, a path from the repo's root for a diff.
    @ObservationIgnored private(set) var place: String?
    /// Opens a link from the page, in the card or beside it (`Page.open(_:arg:at:from:how:)`).
    @ObservationIgnored var open: ((PluginManifest, String, String?, Opening) -> Void)?
    var dirty = false
    /// The page drew its first rows or its file: the loader goes.
    var ready = false
    /// A diff's row 2: Side by Side, and the file list shown. Per card, not saved.
    var split = false {
        didSet { send(["op": "layout", "split": split]) }
    }

    var list = true {
        didSet { send(["op": "list", "open": list]) }
    }

    /// Files: row 2's filter; a page loaded again ends it.
    var filter = ""
    /// The tree's root and its repository, when the root is a repository's root; listings then carry git's state.
    @ObservationIgnored var repo: (root: String, path: String?)?
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
    /// The card had the keyboard when it moved to another place: the new page takes it as it finishes, as WebKit
    /// drops it with the page that had it.
    @ObservationIgnored fileprivate var refocus = false
    /// Git's home: its data and writes, also for row 2.
    @ObservationIgnored private(set) lazy var git = GitRepo(card: self)
    @ObservationIgnored private var css = ""

    init(plugin: String, page: PluginPage, arg: String, place: String?, store: HostStore) {
        self.plugin = plugin
        self.page = page
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
    func theme(_ css: String, _ theme: [String: Any]) {
        self.css = css
        bridge?.theme = theme
        script()
        if loaded {
            view.callAsyncJavaScript("document.documentElement.style.cssText = css", arguments: ["css": css],
                                     in: nil, in: .page)
        } else {
            loaded = true
            guard page == .main else {
                view.load(URLRequest(url: PluginScheme.url(plugin, page)))
                return
            }
            // A plugin's page starts with its saved state, and not at all with an API too new.
            Task {
                await bridge?.start()
                if bridge?.failure == nil {
                    reload()
                }
            }
        }
    }

    /// The page again, from its start: Reload after it stopped.
    func reload() {
        bridge?.failure = nil
        ready = false
        script()
        view.load(URLRequest(url: PluginScheme.url(plugin, page)))
    }

    /// Another place: its page loads with it.
    func show(_ arg: String, at place: String?) {
        // A plugin's page draws its places itself.
        guard page != .main else {
            self.arg = arg
            self.place = place
            bridge?.place(arg, at: place)
            return
        }
        self.arg = arg
        page = PluginPage(plugin, arg) ?? page
        self.place = place
        hash = nil
        toast = nil
        dirty = false
        ready = false
        // The new page starts with none; a filter field shown with text would take the keyboard.
        filter = ""
        refocus = view.window?.firstResponder === view
        if loaded {
            script()
            view.load(URLRequest(url: PluginScheme.url(plugin, page)))
        }
    }

    /// A message to the page's `receive` handler (`web/src/lib/bridge.ts`): row 2's controls. A page reads their first
    /// state from its first ask's reply, so one sent before it listens is no loss.
    func send(_ message: [String: Any]) {
        view.callAsyncJavaScript("window.receive?.(message)", arguments: ["message": message], in: nil, in: .page)
    }

    /// The card's context and colors, in the page before its code runs: a plugin's `oriel_card` (`Bridge.context`),
    /// File Explorer's and Git's `card`.
    private func script() {
        var card: [String: Any] = ["arg": arg, "css": css]
        card["at"] = place
        let name = page == .main ? "oriel_card" : "card"
        if let bridge, page == .main {
            card = bridge.context().merging(["css": css]) { $1 }
        }
        let json = (try? JSONSerialization.data(withJSONObject: card)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
        let content = view.configuration.userContentController
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(
            source: "window.\(name) = \(json); document.documentElement.style.cssText = window.\(name).css",
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
            defer { ready = true }
            return await read()
        case "save":
            // Only a file read: a nil hash would overwrite whatever is on disk. One save at a time: a second would
            // check the first's old hash; its edits keep the dot for the next ⌘S.
            guard !saving, let text = message["text"] as? String, let hash else { return (nil, "Not read") }
            await save(text, over: hash)
        case "symbol", "page", "dirty", "markdown", "ready":
            shows(message)
        case "menu":
            menu(message)
        case "repo":
            return await git.answer(message)
        case "patch":
            defer { ready = true }
            return await patch()
        case "open":
            // No `how`: in the card.
            guard let arg = message["arg"] as? String,
                  let opener = opener(message, arg) else { return (nil, "No path") }
            open?(opener, arg, message["at"] as? String, (message["how"] as? String).flatMap(Opening.init) ?? .here)
        default:
            return await files(message)
        }
        return (nil, nil)
    }

    /// A row's menu at the pointer, after the page's reply: Open (Open as Root for a folder), Open in New Tab, Open to
    /// the Side.
    private func menu(_ message: [String: Any]) {
        guard let arg = message["arg"] as? String, let opener = opener(message, arg) else { return }
        let place = message["at"] as? String, folder = message["folder"] as? Bool == true
        let menu = NSMenu()
        for (title, how) in [(folder ? "Open as Root" : "Open", Opening.here), ("Open in New Tab", .tab),
                             ("Open to the Side", .side)]
        {
            let action = MenuAction { [weak self] in self?.open?(opener, arg, place, how) }
            let item = menu.addItem(withTitle: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            item.target = action
            item.representedObject = action
        }
        Task { @MainActor [view] in
            guard let window = view.window else { return }
            menu.popUp(
                positioning: nil,
                at: view.convert(window.mouseLocationOutsideOfEventStream, from: nil),
                in: view,
            )
        }
    }

    /// The plugin an open from the page names (`kind`), else a file's default plugin; a folder's is File Explorer.
    private func opener(_ message: [String: Any], _ arg: String) -> PluginManifest? {
        if let id = message["kind"] as? String {
            return Registry.plugin(id)
        }
        return arg.hasSuffix("/") ? Registry.plugin("explorer") : Registry.openers(arg).first
    }

    /// A report of what the page shows: the jump bar's symbol, the PDF's page, the dirty dot, Markdown's mode, its
    /// first draw.
    private func shows(_ message: [String: Any]) {
        switch message["op"] as? String {
        case "symbol":
            symbol = message["symbol"] as? String ?? ""
        case "page":
            pdfPage = "\(message["page"] as? Int ?? 1) of \(message["pages"] as? Int ?? 1)"
        case "markdown":
            markdown = (message["edit"] as? Bool == true, message["outline"] as? Bool == true)
        case "ready":
            ready = true
        default:
            dirty = message["dirty"] as? Bool == true
        }
    }
}

/// A menu item's action as a closure: the item keeps it (`representedObject`), its target is weak.
final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
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
        guard let card else { return (nil, "Closed") }
        // A plugin's page has the plugin API alone; File Explorer's and Git's pages the old messages.
        if card.page == .main, let bridge = card.bridge {
            return await bridge.call(message.body as? [String: Any] ?? [:])
        }
        return await card.answer(message.body)
    }

    /// The card's own page only: a Markdown file's HTML (a `<meta>` refresh, a form) would take the view, and the
    /// bridge with it, to any site or to another page.
    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let card else { return .cancel }
        return url == PluginScheme.url(card.plugin, card.page) ? .allow : .cancel
    }

    /// The keyboard back to a card that moved to another place, unless another view took it meanwhile.
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        reloaded = false
        guard let card, card.refocus else { return }
        card.refocus = false
        if let window = card.view.window, window.firstResponder === window || window.firstResponder === card.view {
            card.view.takeKeyboard()
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
        card?.refocus = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !reloaded else { return }
        reloaded = true
        card?.dirty = false
        // A plugin's page again with its state now.
        if card?.page == .main {
            card?.reload()
        } else {
            webView.reload()
        }
    }
}

/// Takes the keyboard as a browser's page does.
final class WebCardView: BrowserView {
    /// The ⇧⌘← or ⇧⌘→ the menu handed to the page: WebKit sends it again when the page leaves it, for Move Tab.
    var handed: NSEvent?
    /// A plugin page's `keyboard`.
    var keyboard: ((Bool) -> Void)?
    /// Back (true) or Forward, ⌘[ and ⌘] over the card, as in a browser; false when there is no place that way, and
    /// the key selects a pane as elsewhere.
    var step: ((Bool) -> Bool)?

    /// WebKit gives the page every ⌘ key first, and CodeMirror takes some of the app's: the menu goes first, as over a
    /// native text view.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if let step, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers, key == "[" || key == "]", step(key == "[")
        {
            return true
        }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true || super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            keyboard?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            keyboard?(false)
        }
        return resigned
    }
}

/// A card's page in the card, with the app's colors and text size: CSS variables on the page's root, and a plugin's
/// `oriel.theme`.
struct WebCardContent: View {
    let card: WebCard
    @Environment(\.self) private var environment
    @Environment(\.look) private var look
    @AppStorage("fontSize") private var textSize = PaneTerminal.fontSize

    var body: some View {
        let colors = [
            ("text", Color.primary), ("dim", look.paneButton), ("divider", look.divider), ("card", look.cardSolid),
            ("accent", .accentColor), ("on-accent", Look.onAccent),
            ("working", look.working), ("needs-you", look.needsYou), ("finished", look.finished),
            ("error", look.error),
        ].map { name, color in
            let rgb = color.resolve(in: environment)
            return (name, "rgb(\(rgb.red * 255) \(rgb.green * 255) \(rgb.blue * 255) / \(rgb.opacity))")
        }
        let css = colors.map { "--\($0): \($1)" }.joined(separator: "; ")
            + "; --app-text-size: \(textSize)px; color-scheme: \(look.dark ? "dark" : "light")"
        WebHost(view: card.view).onChange(of: css, initial: true) {
            card.theme(css, ["dark": look.dark, "style": look.style.rawValue, "textSize": textSize,
                             "colors": Dictionary(uniqueKeysWithValues: colors)])
        }
    }
}
