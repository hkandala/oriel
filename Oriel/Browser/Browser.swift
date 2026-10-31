import AppKit
import HerdrKit
import Observation
import WebKit

/// A browser pane's card (ui/browser): its web view and what the toolbar shows. Built once from the label; the
/// registry keeps it, so a tab shown again does not reload it.
@MainActor @Observable
final class Browser: NSObject {
    let terminalID: String
    var paneID: String
    let label: PaneLabel
    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: BrowserView
    /// As the address field shows it when not editing; empty before the first load.
    private(set) var address = ""
    private(set) var title = ""
    /// The page's icon and where it came from; nil: the globe.
    var icon: (href: String, image: NSImage?)?
    private(set) var loading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// A failed load, in the app's words, and the line under it.
    private(set) var failure: (text: String, hint: String?)?
    /// A page from an origin not approved, which the machine put in the label or the state file: "Open ‹url›?".
    private(set) var asking: URL?
    /// The web view has shown a page; until then it stays hidden (an empty one draws white).
    private(set) var loaded = false
    /// The loader shows until the first page drew, or at once with nothing to load.
    private(set) var ready = false
    /// A `window.open` page (OAuth needs its opener) over the card, and its host.
    var popup: (view: WKWebView, host: String)?
    /// The address field takes the keyboard when it shows, or now (⌘L, a new empty card).
    var wantsAddress = false
    /// The pane got the keyboard while the state file was read: given once the address is known.
    @ObservationIgnored private var claimed = false
    @ObservationIgnored private var reading = true
    /// The label's address this card follows (`follow`): the one it was built from or its last rename.
    @ObservationIgnored private var labelled: String
    /// The address `labelled` replaced: a snapshot read before the rename still has it.
    @ObservationIgnored private var replaced: String?
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
        labelled = label.arg
        // A new pane has no state file to read: its address field takes the keyboard at once (a claim held across a
        // read is lost when the replaced pane's view leaves).
        reading = !label.arg.isEmpty
        self.store = store
        let machine = store.machine
        alias = machine.isRemote ? Self.alias(machine.name) : nil
        let configuration = WKWebViewConfiguration()
        let data = Self.dataStore(machine)
        configuration.websiteDataStore = data
        // Sites that sniff for Safari work.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        // `_inspector show` opens nothing without it.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        view = BrowserView(frame: .zero, configuration: configuration)
        super.init()
        if machine.isRemote {
            let content = view.configuration.userContentController
            proxy = Task { await Self.proxy(machine, data, content) }
        }
        // Safari's Develop menu reaches every card.
        view.isInspectable = true
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self
        view.uiDelegate = self
        view.onKey = { [weak self] in self?.key($0) ?? false }
        view.setAccessibilityIdentifier("browser.\(paneID)")
        watches = watch()
        Task { await start() }
    }

    /// The toolbar's values, by KVO on the main thread, where WebKit changes them.
    private func watch() -> [NSKeyValueObservation] {
        func mirror(_ path: KeyPath<BrowserView, some Any>,
                    _ update: @escaping @MainActor (Browser) -> Void) -> NSKeyValueObservation
        {
            view.observe(path) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    if let self {
                        update(self)
                    }
                }
            }
        }
        return [
            mirror(\.isLoading) { $0.loading = $0.view.isLoading },
            mirror(\.estimatedProgress) { $0.progress = $0.view.estimatedProgress },
            mirror(\.canGoBack) { $0.canGoBack = $0.view.canGoBack },
            mirror(\.canGoForward) { $0.canGoForward = $0.view.canGoForward },
            mirror(\.title) { $0.title = $0.view.title ?? "" },
            mirror(\.url) { browser in
                guard let url = browser.view.url, url.absoluteString != "about:blank" else { return }
                browser.address = Self.shown(url, browser.alias).absoluteString
                // A single-page app's route (`pushState`) finishes no navigation.
                if browser.loaded {
                    browser.save()
                }
            },
        ]
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

    /// The address field's Return; the label gets the typed address.
    func go(_ text: String) {
        guard let store, let url = Self.url(text, local: !store.machine.isRemote) else { return }
        asking = nil
        approve(url)
        load(url)
        replaced = labelled
        labelled = url.absoluteString
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

    /// Esc closes the popup; Return opens and Esc dismisses "Open this page?" while the card has the keyboard.
    func key(_ event: NSEvent) -> Bool {
        if popup != nil, event.keyCode == 53 {
            closePopup()
            return true
        }
        guard asking != nil, [36, 76, 53].contains(event.keyCode) else { return false }
        if event.keyCode == 53 {
            notNow()
        } else {
            open()
        }
        return true
    }

    /// "Not now": the page it had, or none.
    func notNow() {
        asking = nil
        history = nil
        address = view.url?.absoluteString ?? ""
    }

    /// The label got another address from elsewhere (an agent's `herdr pane rename`): it loads as a new page in the
    /// card's history, by the load rule.
    func follow(_ arg: String) {
        guard arg != labelled, arg != replaced, let store else { return }
        replaced = nil
        labelled = arg
        guard let url = Self.url(arg, local: !store.machine.isRemote) else { return }
        address = url.absoluteString
        if approved(url) {
            load(url)
        } else {
            asking = url
        }
    }

    /// The saved page with its back and forward list, else the address alone.
    /// The history's current page must pass the load rule too: a process on the machine writes the state file.
    private func restore(_ url: URL) {
        if let history {
            self.history = nil
            proxied {
                self.view.interactionState = history
                guard let current = (self.view.backForwardList.currentItem?.url).map({ Self.shown($0, self.alias) }),
                      Self.origin(current) != Self.origin(url), !self.approved(current) else { return }
                self.view.stopLoading()
                self.asking = current
            }
        } else {
            load(url)
        }
    }

    func reload() {
        guard asking == nil else { return }
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
        // Only a change: Observation reports equal writes too.
        if wantsAddress {
            wantsAddress = false
        }
    }

    /// A save still pending would bring back the state file a close removed.
    isolated deinit {
        saving?.cancel()
        if let proxy {
            Task { await proxy.value?.closeProxy() }
        }
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
        loaded = true
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        ready = true
        reloaded = false
        save()
        loadIcon()
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
        failure = failureText(error, url)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !reloaded else { return }
        reloaded = true
        webView.reload()
    }

    /// A `mailto:` or an app's link clicked in the page goes to its app; the page stays. Never from script or a frame.
    /// A ⌘-clicked page opens in a new tab.
    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command),
           let url = action.request.url, openTab(url)
        {
            return .cancel
        }
        // A remote page's link or redirect to `localhost` means its machine's, sent as it is (an OAuth `form_post`
        // keeps its body). The content rule blocks the rest (`proxy`).
        if alias != nil, action.targetFrame?.isMainFrame == true, let url = action.request.url,
           Self.loopback.contains(url.host?.lowercased() ?? "")
        {
            var request = action.request
            request.url = Self.web(url, alias)
            proxied { self.view.load(request) }
            return .cancel
        }
        // A remote card never shows This Mac's files (a history entry or a script may ask for one).
        if alias != nil, action.request.url?.isFileURL == true {
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
