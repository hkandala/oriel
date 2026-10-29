import AppKit
import HerdrKit
import WebKit

/// What a page asks of its card: new windows, dialogs and file panels.
extension Browser: WKUIDelegate {
    /// `window.open` (an OAuth popup keeps its opener) in a sheet over the card. A link that asks for a new window
    /// (`target=_blank`) and Open Link in New Tab open a tab; a form that does loads in the card.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView?
    {
        let view = webView as? BrowserView
        if view?.opensTab == true || action.navigationType == .linkActivated {
            view?.opensTab = false
            if let url = action.request.url {
                openTab(url)
            }
            return nil
        }
        guard action.navigationType == .other else {
            webView.load(action.request)
            return nil
        }
        let popup = BrowserView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.onKey = { [weak self] in self?.key($0) ?? false }
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
    func closePopup() {
        popup = nil
        view.takeKeyboard()
    }

    /// Open Link in New Tab, ⌘-click and `target=_blank`: a browser pane on the link in a new tab after the
    /// workspace's others, left in the background as Safari does. The user picked the link: its origin is approved,
    /// so the new card loads it. False for an address a label cannot hold.
    @discardableResult
    func openTab(_ link: URL) -> Bool {
        guard let store, let pane = store.pane(paneID), let workspace = store.workspace(of: pane.tabID),
              let url = Self.url(Self.shown(link, alias).absoluteString, local: !store.machine.isRemote)
        else { return false }
        approve(url)
        let taken = Set(store.panes.compactMap { PaneLabel($0.label)?.iid })
        let label = PaneLabel(plugin: "browser", iid: PaneLabel.newIID(taken: taken), arg: url.absoluteString)
        Task {
            await store.write {
                _ = try await $0.newTab(workspace: workspace.id, cwd: pane.cwd ?? "~", label: label.text,
                                        command: Self.placeholder(label))
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
