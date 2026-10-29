import AppKit
import Network
import WebKit

/// What a page asks of its card: new windows, dialogs and file panels.
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

extension Browser {
    /// The page's icon after each load: its `<link rel=icon>`, else `/favicon.ico`; nil (the globe) when it does not
    /// load. WebKit has no favicon API. Fetched through the card's proxy; a remote card's only from its page's host,
    /// which its proxy asks the machine for.
    func loadIcon() {
        Task {
            let script = "return document.querySelector('link[rel~=icon]')?.href ?? null"
            let href = try? await view.callAsyncJavaScript(script, contentWorld: .defaultClient) as? String
            let fallback = view.url.flatMap { URL(string: "/favicon.ico", relativeTo: $0)?.absoluteURL }
            guard let page = view.url, let url = href.flatMap(URL.init(string:)) ?? fallback, url != icon?.url
            else { return }
            icon = (url, icon?.image)
            let image = await Self.image(url, page: page, remote: alias != nil,
                                         proxies: view.configuration.websiteDataStore.proxyConfigurations)
            // Not over a newer page's.
            if icon?.url == url {
                icon = (url, image)
            }
        }
    }

    private static func image(_ url: URL, page: URL, remote: Bool, proxies: [ProxyConfiguration]) async -> NSImage? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "data"].contains(scheme), !remote || scheme == "data" || url.host == page.host
        else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = proxies
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ $0.statusCode < 300 }) ?? true, data.count < 1 << 20
        else { return nil }
        return NSImage(data: data)
    }
}
