import AppKit
import HerdrKit
import Observation
import WebKit

/// A browser pane's card (future-work/web-page): its web view and what the toolbar shows. Built from the label once;
/// an open card follows no rename (future-work/plugins/state#when-a-card-reads-its-state). The registry keeps it, so
/// a tab shown again does not reload it.
@MainActor @Observable
final class Browser: NSObject {
    let terminalID: String
    var paneID: String
    let label: PaneLabel
    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: BrowserView
    /// The page's address, as the address field shows it when not editing; empty before the first load.
    private(set) var address = ""
    private(set) var title = ""
    private(set) var loading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// A failed load, in the app's words, and the line under it.
    private(set) var failure: (text: String, hint: String?)?
    /// A page the machine put in the label or the state file, from an origin not approved: "Open ‹url›?".
    private(set) var asking: URL?
    /// The loader shows until the first page drew, or at once with nothing to load.
    private(set) var ready = false
    /// A `window.open` page (OAuth needs its opener) in a sheet over the card, until it closes.
    private(set) var popup: WKWebView?
    /// The address field takes the keyboard when it shows, or now (⌘L, a new empty card).
    var wantsAddress = false
    @ObservationIgnored private var watches: [NSKeyValueObservation] = []
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(terminalID: String, paneID: String, label: PaneLabel, store: HostStore) {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        self.store = store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.dataStore(store.machine)
        // Sites that sniff for Safari work.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        view = BrowserView(frame: .zero, configuration: configuration)
        super.init()
        view.isInspectable = true
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self
        view.uiDelegate = self
        view.setAccessibilityIdentifier("browser.\(paneID)")
        // KVO on the main thread: WebKit changes these there.
        watches = [
            view
                .observe(\.isLoading) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.loading = view.isLoading }
                },
            view.observe(\.estimatedProgress) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.progress = view.estimatedProgress }
            },
            view
                .observe(\.canGoBack) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
                },
            view.observe(\.canGoForward) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            view
                .observe(\.title) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.title = view.title ?? "" }
                },
            view.observe(\.url) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    if let url = view.url?.absoluteString, url != "about:blank" {
                        self?.address = url
                    }
                }
            },
        ]
        Task { await start() }
    }

    /// The load rule: the saved address (the state file on the pane's machine), else the label's; a machine's own
    /// page loads by itself only from an approved or safe origin.
    private func start() async {
        guard let store else { return }
        let saved = await store.machine.exec().read(home: label.statePath(session: store.session))
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }?["url"] as? String
        guard let url = Self.url(saved ?? label.arg, local: !store.machine.isRemote) else {
            ready = true
            return
        }
        address = url.absoluteString
        if approved(url) {
            load(url)
        } else {
            asking = url
            ready = true
        }
    }

    /// The address field's Return: a bare `host:port` gets `http://`. The label gets the typed address.
    func go(_ text: String) {
        guard let store, let url = Self.url(text, local: !store.machine.isRemote) else { return }
        approve(url)
        load(url)
        let label = PaneLabel(plugin: label.plugin, iid: label.iid, arg: url.absoluteString)
        Task { await store.rename(pane: paneID, label: label.text) }
        view.takeKeyboard()
    }

    /// The "Open ‹url›?" answer.
    func open() {
        guard let url = asking else { return }
        asking = nil
        approve(url)
        load(url)
    }

    func reload() {
        if failure != nil || view.url == nil, let url = URL(string: address) {
            load(url)
        } else {
            view.reload()
        }
    }

    private func load(_ url: URL) {
        failure = nil
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url))
        }
    }

    /// The pane's keyboard: the page, or the address field while there is no page.
    func takeKeyboard() {
        if address.isEmpty {
            wantsAddress = true
        } else {
            view.takeKeyboard()
        }
    }

    /// WebKit's own Web Inspector window for this page. No public API shows it: `_WKInspector` (cmux ships it);
    /// Safari's Develop menu reaches every card too (`isInspectable`).
    func showInspector() {
        let inspector = NSSelectorFromString("_inspector")
        guard view.responds(to: inspector), let object = view.perform(inspector)?.takeUnretainedValue() as? NSObject
        else { return }
        let show = NSSelectorFromString("show"), detach = NSSelectorFromString("detach")
        guard object.responds(to: show), object.responds(to: detach) else { return }
        // `show` docks it under the page, and `detach` moves it to its own window only once it loaded (about 1 s).
        let windows = { NSApp.windows.filter { $0.isVisible && $0.title.hasPrefix("Web Inspector") }.count }
        let before = windows()
        object.perform(show)
        Task {
            for _ in 0 ..< 20 where windows() == before {
                try? await Task.sleep(for: .milliseconds(200))
                object.perform(detach)
            }
        }
    }

    func closePopup() {
        popup = nil
    }

    /// The pane's command in herdr (future-work/web-page#in-herdrs-tui): "Browser", the address it started with, and
    /// "Shown in Oriel", centered and drawn again on a resize. Keys do nothing: `stty raw` makes Ctrl-C and Ctrl-D
    /// plain bytes for the `cat` that swallows them. herdr runs the argv itself, with no shell quoting.
    static func placeholder(_ label: PaneLabel) -> [String] {
        let script = #"""
        draw() {
          set -- $(stty size 2>/dev/null || echo "24 80"); r=$1 c=$2
          printf '\033[?25l\033[2J'
          line() {
            x=$(( (c - ${#2}) / 2 + 1 )); [ $x -lt 1 ] && x=1
            printf '\033[%d;%dH%b%s\033[0m' "$1" "$x" "$3" "$2"
          }
          y=$(( r / 2 - 2 ))
          line $y "$T" '\033[1m'
          [ -n "$U" ] && line $((y + 2)) "$U" '\033[4;34m'
          line $((y + 4)) "Shown in Oriel" '\033[2m'
        }
        T=$1 U=$2
        stty raw -echo 2>/dev/null
        trap draw WINCH
        draw
        cat <&0 >/dev/null &
        while kill -0 $! 2>/dev/null; do wait $!; done
        """#
        return ["sh", "-c", script, "sh", "Browser", label.arg]
    }

    // MARK: Origins

    /// The machine's own loopback on any port, This Mac's files, and a few developer sites.
    private static let safe = ["github.com", "gitlab.com", "bitbucket.org", "developer.apple.com",
                               "developer.mozilla.org", "docs.github.com", "vercel.com"]

    private func approved(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.isFileURL }
        return ["localhost", "127.0.0.1", "::1"].contains(host) || Self.safe.contains(host)
            || host.hasSuffix(".vercel.app") || host.hasSuffix(".netlify.app") || approvals.contains(Self.origin(url))
    }

    private func approve(_ url: URL) {
        guard !approved(url) else { return }
        UserDefaults.standard.set(approvals + [Self.origin(url)], forKey: approvalsKey)
    }

    /// Per device, per machine.
    private var approvalsKey: String {
        "browserApprovals.\(store?.machine.id ?? "")"
    }

    private var approvals: [String] {
        UserDefaults.standard.stringArray(forKey: approvalsKey) ?? []
    }

    private static func origin(_ url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host ?? "")" + (url.port.map { ":\($0)" } ?? "")
    }

    /// `http`, `https`, and `file` on This Mac only; at most 1024 characters (the label's argument).
    static func url(_ text: String, local: Bool) -> URL? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 1024 else { return nil }
        let full = text.contains("://") ? text : "http://\(text)"
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased() else { return nil }
        return ["http", "https"].contains(scheme) && url.host != nil || scheme == "file" && local ? url : nil
    }

    // MARK: Storage

    /// One store per machine (future-work/web-page#profiles): cookies, storage and the cache stay apart.
    private static var stores: [String: WKWebsiteDataStore] = [:]

    private static func dataStore(_ machine: Machine) -> WKWebsiteDataStore {
        if let store = stores[machine.id] {
            return store
        }
        // This Mac's fixed id ("oriel" … "thisMa"); a remote machine's from its id.
        let id = UUID(uuidString: machine.id)
            ?? UUID(uuid: (0x6F, 0x72, 0x69, 0x65, 0x6C, 0, 0x40, 0, 0x80, 0, 0x74, 0x68, 0x69, 0x73, 0x4D, 0x61))
        let store = WKWebsiteDataStore(forIdentifier: id)
        stores[machine.id] = store
        return store
    }

    /// The address after a navigation, on the pane's machine, 500 ms after the last one; last writer wins.
    private func save() {
        guard let store, let url = view.url?.absoluteString, url != "about:blank",
              let data = try? JSONSerialization.data(withJSONObject: ["url": url]) else { return }
        let path = label.statePath(session: store.session), line = String(decoding: data, as: UTF8.self)
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await store.machine.exec().write(home: path, line)
        }
    }
}

extension Browser: WKNavigationDelegate {
    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        failure = nil
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        ready = true
        if let url = webView.url {
            approve(url)
        }
        save()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    private func failed(_ error: any Error) {
        ready = true
        let error = error as NSError
        // A load replaced by another, or a download.
        guard error.code != NSURLErrorCancelled,
              error.domain != "WebKitErrorDomain" || error.code != 102 else { return }
        let url = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? URL(string: address)
        let place = url.map { [$0.host, $0.port.map(String.init)].compactMap(\.self).joined(separator: ":") } ?? ""
        let local = url?.host.map { ["localhost", "127.0.0.1", "::1"].contains($0) } ?? false
        failure = switch error.code {
        case NSURLErrorCannotConnectToHost where local: ("Nothing answers on \(place)", "Is the dev server running?")
        case NSURLErrorCannotFindHost: ("Cannot find \(place)", nil)
        default: (error.localizedDescription, nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension Browser: WKUIDelegate {
    /// `window.open` (an OAuth popup keeps its opener) in a sheet over the card; a link that asks for a new window
    /// without script opens in the card.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView?
    {
        guard action.navigationType == .other else {
            webView.load(action.request)
            return nil
        }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.setAccessibilityIdentifier("browser.\(paneID).popup")
        self.popup = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup {
            popup = nil
        }
    }

    /// Page dialogs as a sheet on the window, labeled with the origin.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async
    {
        _ = await dialog(webView, message, frame, buttons: ["OK"])
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool
    {
        await dialog(webView, message, frame, buttons: ["OK", "Cancel"]) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame _: WKFrameInfo) async -> [URL]?
    {
        guard let window = webView.window else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
    }

    private func dialog(_ webView: WKWebView, _ message: String, _ frame: WKFrameInfo,
                        buttons: [String]) async -> NSApplication.ModalResponse
    {
        guard let window = webView.window else { return .cancel }
        let alert = NSAlert()
        let origin = frame.securityOrigin, port = origin.port > 0 ? ":\(origin.port)" : ""
        alert.messageText = (origin.host.isEmpty ? origin.protocol : origin.host) + port
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return await alert.beginSheetModal(for: window)
    }
}
