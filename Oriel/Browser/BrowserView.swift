import AppKit
import WebKit

/// The web view, which takes the keyboard as a terminal does (`PaneSurfaceView`): now, or once it is in a window.
final class BrowserView: WKWebView {
    var onKeyboard: (() -> Void)?
    /// A key the card takes before the page (its "Open this page?").
    var onKey: ((NSEvent) -> Bool)?
    private var wantsKeyboard = false
    /// Open ‹Link› in New Tab was picked: the page asks for its new window next (`createWebViewWith`).
    var opensTab = false

    /// The key window's browser that has the keyboard: ⌘+ ⌘− ⌘0 zoom its page.
    static var focused: BrowserView? {
        NSApp.keyWindow?.firstResponder as? BrowserView
    }

    func takeKeyboard() {
        wantsKeyboard = true
        // After SwiftUI's update: a first responder set during one is undone.
        DispatchQueue.main.async { [weak self] in
            guard let self, wantsKeyboard, let window else { return }
            wantsKeyboard = false
            window.makeFirstResponder(self)
        }
    }

    /// Per card, ⌘+ ⌘− ⌘0 while it has the keyboard (the font size items); 0 resets.
    func zoom(_ step: Int) {
        pageZoom = step == 0 ? 1 : min(3, max(0.5, pageZoom + CGFloat(step) * 0.1))
    }

    /// The menu holds no address: a New Tab item sends its New Window item's action, which asks for a new window
    /// with the link's address, and `opensTab` makes that a tab. No downloads: the app does not save them.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        opensTab = false
        menu.items = menu.items.compactMap { item in
            let id = item.identifier?.rawValue ?? ""
            guard !id.hasPrefix("WKMenuItemIdentifierDownload") else { return nil }
            guard id.hasSuffix("InNewWindow") else { return item }
            let tab = NSMenuItem(title: item.title.replacingOccurrences(of: "New Window", with: "New Tab"),
                                 action: #selector(openTab), keyEquivalent: "")
            tab.target = self
            tab.representedObject = item
            return tab
        }
    }

    @objc private func openTab(_ tab: NSMenuItem) {
        guard let item = tab.representedObject as? NSMenuItem, let action = item.action else { return }
        opensTab = true
        NSApp.sendAction(action, to: item.target, from: item)
    }

    /// A pick WebKit never asked a window for (New Tab on a `mailto:` link) must not make the page's next popup a tab
    /// (also from a key, `keyDown`).
    override func mouseDown(with event: NSEvent) {
        opensTab = false
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        opensTab = false
        if onKey?(event) != true {
            super.keyDown(with: event)
        }
    }

    func dropClaim() {
        wantsKeyboard = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsKeyboard, window != nil {
            takeKeyboard()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onKeyboard?()
        }
        return became
    }
}
