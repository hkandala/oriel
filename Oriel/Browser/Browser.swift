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
    /// Its address's host, its title.
    private(set) var popupHost = ""
    /// The address field takes the keyboard when it shows, or now (⌘L, a new empty card).
    var wantsAddress = false
    /// The pane got the keyboard while the state file was read: given once the address is known.
    @ObservationIgnored private var claimed = false
    @ObservationIgnored private var reading = true
    /// The saved back and forward list (WebKit's `interactionState`), restored with the saved page.
    @ObservationIgnored private var history: Data?
    /// The page's process ended since the last load finished: it loads again once.
    @ObservationIgnored private var reloaded = false
    @ObservationIgnored private var watches: [NSKeyValueObservation] = []
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// A remote machine's `<machine>` in `<machine>.localhost`, and its proxy, which every load waits for.
    @ObservationIgnored let alias: String?
    @ObservationIgnored private var proxy: Task<SSHExec?, Never>?

    init(terminalID: String, paneID: String, label: PaneLabel, store: HostStore) {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        self.store = store
        let machine = store.machine
        alias = machine.isRemote ? Self.alias(machine.name) : nil
        let configuration = WKWebViewConfiguration()
        let data = Self.dataStore(machine)
        configuration.websiteDataStore = data
        // Sites that sniff for Safari work.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        // `_inspector show` opens nothing without it (checked).
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        view = BrowserView(frame: .zero, configuration: configuration)
        super.init()
        if machine.isRemote {
            proxy = Task { await Self.proxy(machine, data) }
        }
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
                    if let self, let url = view.url, url.absoluteString != "about:blank" {
                        self.address = Self.shown(url, self.alias).absoluteString
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
        let state = await store.machine.exec().read(home: label.statePath(session: store.session))
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let saved = state?["url"] as? String
        history = saved == nil ? nil : (state?["history"] as? String).flatMap { Data(base64Encoded: $0) }
        reading = false
        defer {
            if claimed {
                claimed = false
                takeKeyboard()
            }
        }
        // Not over an address typed meanwhile.
        guard address.isEmpty, let url = Self.url(saved ?? label.arg, local: !store.machine.isRemote) else {
            ready = true
            return
        }
        address = url.absoluteString
        if approved(url) {
            restore(url)
        } else {
            asking = url
            ready = true
        }
    }

    /// The address field's Return: a bare `host:port` gets `http://`. The label gets the typed address.
    func go(_ text: String) {
        guard let store, let url = Self.url(text, local: !store.machine.isRemote) else { return }
        approve(url)
        // The loader until the first page drew, not the white of an empty web view.
        if address.isEmpty {
            ready = false
        }
        load(url)
        // The saved address goes: a typed load that fails opens the typed one after a relaunch.
        saving?.cancel()
        let path = label.statePath(session: store.session)
        Task { await store.machine.exec().remove(home: path) }
        let label = PaneLabel(plugin: label.plugin, iid: label.iid, arg: url.absoluteString)
        Task { await store.rename(pane: paneID, label: label.text) }
        view.takeKeyboard()
    }

    /// The "Open ‹url›?" answer.
    func open() {
        guard let url = asking else { return }
        asking = nil
        approve(url)
        restore(url)
    }

    /// The saved page with its back and forward list, else the address alone.
    private func restore(_ url: URL) {
        if let history {
            self.history = nil
            proxied { self.view.interactionState = history }
        } else {
            load(url)
        }
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
            proxied { self.view.load(URLRequest(url: Self.web(url, self.alias))) }
        }
    }

    /// At once on This Mac; on a remote machine once its proxy is in the store, never without it:
    /// `<machine>.localhost` would reach This Mac.
    private func proxied(_ load: @escaping () -> Void) {
        guard let proxy else { return load() }
        Task {
            guard await proxy.value != nil else {
                failure = ("Oriel could not start the proxy to \(store?.machine.name ?? "")", nil)
                ready = true
                return
            }
            load()
        }
    }

    /// The pane's keyboard: the page, or the address field while there is no page.
    func takeKeyboard() {
        if reading {
            claimed = true
        } else if address.isEmpty {
            wantsAddress = true
        } else {
            view.takeKeyboard()
        }
    }

    /// Another card of the window asked for the keyboard.
    func dropClaim() {
        view.dropClaim()
        claimed = false
        if wantsAddress {
            wantsAddress = false
        }
    }

    /// WebKit's Web Inspector for this page, docked under it as Inspect Element opens it; its own control moves it to
    /// a window. No public API shows it: `_WKInspector` (cmux ships it); Safari's Develop menu reaches every card too
    /// (`isInspectable`).
    func showInspector() {
        let inspector = NSSelectorFromString("_inspector"), show = NSSelectorFromString("show")
        guard view.responds(to: inspector), let object = view.perform(inspector)?.takeUnretainedValue() as? NSObject,
              object.responds(to: show) else { return }
        // Docked each time: WebKit keeps the last choice of a window in the app's defaults.
        // ponytail: WebKit's private key; if it changes, the inspector opens as it was left.
        UserDefaults.standard.removeObject(forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
        object.perform(show)
    }

    /// A save still pending would bring back the state file a close removed.
    isolated deinit {
        saving?.cancel()
        if let proxy {
            Task { await proxy.value?.closeProxy() }
        }
    }

    func closePopup() {
        popup = nil
    }

    /// The address after a navigation, on the pane's machine, 500 ms after the last one; last writer wins.
    /// The back and forward list too, while it is under 128 KiB (the state file holds at most 256 KiB).
    private func save() {
        guard let store, let url = view.url.map({ Self.shown($0, alias).absoluteString }), url != "about:blank"
        else { return }
        var state = ["url": url]
        if let history = view.interactionState as? Data, history.count < 128 << 10 {
            state["history"] = history.base64EncodedString()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
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
        reloaded = false
        if let url = webView.url {
            approve(Self.shown(url, alias))
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
        let url = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL).map { Self.shown($0, alias) }
            ?? URL(string: address)
        let place = url.map { [$0.host, $0.port.map(String.init)].compactMap(\.self).joined(separator: ":") } ?? ""
        let local = url?.host.map { Self.loopback.contains($0) } ?? false
        // The proxy refuses a port that does not answer and a name the machine cannot reach; WebKit reports either
        // code for it (checked).
        let machine = alias == nil ? nil : store?.machine.name
        let refused = error.code == NSURLErrorCannotConnectToHost || machine != nil && error.code == NSURLErrorBadURL
        failure = if refused, let machine, store?.state != .live {
            ("\(machine) is not connected", nil)
        } else if refused, local {
            ("Nothing answers on \(place)" + (machine.map { " on \($0)" } ?? ""), "Is the dev server running?")
        } else if refused, let machine {
            ("\(machine) cannot reach \(place)", nil)
        } else if error.code == NSURLErrorCannotFindHost {
            ("Cannot find \(place)", nil)
        } else {
            (error.localizedDescription, nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !reloaded else { return }
        reloaded = true
        webView.reload()
    }

    /// A `mailto:` or an app's link clicked in the page goes to its app; the page stays. Never from script or a frame.
    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // A remote page's link or redirect to `localhost` means its machine's.
        if alias != nil, action.targetFrame?.isMainFrame == true, let url = action.request.url,
           Self.loopback.contains(url.host?.lowercased() ?? "")
        {
            load(url)
            return .cancel
        }
        guard let url = action.request.url,
              !["http", "https", "file", "about", "blob", "data"].contains(url.scheme?.lowercased() ?? "")
        else { return .allow }
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false {
            NSWorkspace.shared.open(url)
        }
        return .cancel
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
        popupHost = action.request.url?.host ?? ""
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
