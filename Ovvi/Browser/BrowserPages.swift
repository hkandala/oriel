import AppKit
import HerdrKit
import WebKit

/// How a card's pages load, fail and follow links.
extension Browser: WKNavigationDelegate {
    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        failure = nil
        loaded = true
        showAddress()
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
        if let url {
            address = url.absoluteString
        }
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
        if store?.machine.isRemote != false, action.request.url?.isFileURL == true {
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

/// What a page asks of its card: new windows, dialogs and file panels.
extension Browser: WKUIDelegate {
    /// `window.open` (an OAuth popup keeps its opener) in a sheet over the card. A link that asks for a new window
    /// (`target=_blank`, also `rel=opener`: WebKit does not say) and Open Link in New Tab open a tab; a form that
    /// does, and a page no label can hold (`blob:`), load in the card.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView?
    {
        let source = webView as? BrowserView
        let tab = source?.opensTab == true || action.navigationType == .linkActivated
        source?.opensTab = false
        if tab, let url = action.request.url, openTab(url) {
            return nil
        }
        guard action.navigationType == .other, !tab else {
            webView.load(action.request)
            return nil
        }
        let popup = BrowserView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.onKey = { [weak self] in self?.key($0) ?? false }
        popup.onKeyboard = view.onKeyboard
        popup.setAccessibilityIdentifier("browser.\(paneID).popup")
        popup.takeKeyboard()
        self.popup = (popup, action.request.url?.host ?? "")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup?.view {
            closePopup()
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

extension Browser {
    /// The page takes the keyboard back if the popup had it: one that closes itself leaves the user's typing alone.
    func closePopup() {
        let had = popup.map { $0.view.window?.firstResponder === $0.view } ?? false
        popup = nil
        if had {
            view.takeKeyboard()
        }
    }

    /// Open Link in New Tab, ⌘-click and `target=_blank`: a browser pane on the link in a new tab after the
    /// workspace's others, left in the background as Safari does. The user picked the link: its origin is approved,
    /// so the new card loads it. False for an address a label cannot hold.
    @discardableResult
    func openTab(_ link: URL) -> Bool {
        // Not `mailto:`: `url` reads an address without `://` as a host.
        guard ["http", "https", "file"].contains(link.scheme?.lowercased() ?? ""), let store,
              let pane = store.pane(paneID), let workspace = store.workspace(of: pane.tabID),
              let url = Self.url(Self.shown(link, alias).absoluteString, local: !store.machine.isRemote)
        else { return false }
        approve(url)
        let label = store.newLabel(Registry.browser, arg: url.absoluteString)
        // On the network of the card it came from, whatever the setting for new cards.
        if store.machine.isRemote {
            Self.keep(viaMac, "\(store.session)/\(label.iid)", store.machine)
        }
        Task {
            await store.write {
                _ = try await $0.newTab(workspace: workspace.id, cwd: pane.cwd ?? "~", label: label,
                                        command: label.placeholder)
            }
        }
        return true
    }

    /// WebKit has no favicon API: the page fetches its icon, so its proxy, its rules and CORS apply as to any fetch.
    func loadIcon() {
        let page = view.url
        Task {
            let found = try? await view.callAsyncJavaScript(Self.iconScript, arguments: ["known": icon?.href ?? ""],
                                                            contentWorld: .defaultClient) as? [Any]
            // Not over a newer page's.
            guard view.url == page, let href = found?.first as? String, href != icon?.href else { return }
            icon = (href, (found?.last as? String).flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:)))
        }
    }

    /// `[href, base64 or null]`; just the href when it is the one the card has. At most 1 MiB, in 5 s.
    private static let iconScript = """
    const link = document.querySelector('link[rel~=icon]')
    const href = link ? link.href : new URL('/favicon.ico', location.href).href
    if (href === known) return [href, null]
    try {
      const response = await fetch(href, { signal: AbortSignal.timeout(5000) })
      const blob = await response.blob()
      if (!response.ok || blob.size > 1048576) return [href, null]
      let text = ''
      for (const byte of new Uint8Array(await blob.arrayBuffer())) text += String.fromCharCode(byte)
      return [href, btoa(text)]
    } catch { return [href, null] }
    """
}
