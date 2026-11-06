import AppKit
import UniformTypeIdentifiers
import WebKit

/// The web view, which takes the keyboard as a terminal does (`PaneSurfaceView`): now, or once it is in a window.
class BrowserView: WKWebView {
    var onKeyboard: (() -> Void)?
    /// A key the card takes before the page (its "Open this page?").
    var onKey: ((NSEvent) -> Bool)?
    private var wantsKeyboard = false
    /// Open ‹Link› in New Tab or Open Link to the Side was picked: the page asks for its new window next
    /// (`createWebViewWith`).
    var opens: Opening?
    /// In an overview's tile (D70): keys go to the overview; a claim waits until the card has it back.
    var inTile = false
    /// The page's last picture (`takePicture`): its overview tile, and its card's while a card made again loads.
    /// Observed: a tile shows it as it comes.
    let shot = Shot()
    @MainActor @Observable final class Shot {
        var image: CGImage?
    }

    /// A browser card's, on its machine's store (or This Mac's).
    convenience init(store: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        // Sites that sniff for Safari work.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        // `_inspector show` opens nothing without it.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        self.init(frame: .zero, configuration: configuration)
        // Safari's Develop menu reaches every card.
        isInspectable = true
        allowsBackForwardNavigationGestures = true
    }

    /// The key window's browser that has the keyboard: ⌘+ ⌘− ⌘0 zoom its page.
    static var focused: BrowserView? {
        // Not a web card's: it keeps its text size, and the keys size the terminals' text.
        (NSApp.keyWindow?.firstResponder as? BrowserView).flatMap { $0 is WebCardView ? nil : $0 }
    }

    func takeKeyboard() {
        wantsKeyboard = true
        // After SwiftUI's update: a first responder set during one is undone.
        DispatchQueue.main.async { [weak self] in
            guard let self, wantsKeyboard, !inTile, let window else { return }
            wantsKeyboard = false
            window.makeFirstResponder(self)
        }
    }

    /// With no page (a card that asks "Open this page?", or is empty), the menu first: WebKit sends the key to a page
    /// that is not there, and ⌘1–⌘9 were lost.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        url == nil && window?.firstResponder === self && NSApp.mainMenu?.performKeyEquivalent(with: event) == true
            || super.performKeyEquivalent(with: event)
    }

    /// Per card, ⌘+ ⌘− ⌘0 while it has the keyboard (the font size items); 0 resets.
    func zoom(_ step: Int) {
        pageZoom = step == 0 ? 1 : min(3, max(0.5, pageZoom + CGFloat(step) * 0.1))
    }

    /// The menu holds no address: a New Tab item (and a link's to the Side) sends its New Window item's action, which
    /// asks for a new window with the link's address, and `opens` makes that a tab or a side pane. No downloads: the
    /// app does not save them.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        opens = nil
        menu.items = menu.items.flatMap { item -> [NSMenuItem] in
            let id = item.identifier?.rawValue ?? ""
            guard !id.hasPrefix("WKMenuItemIdentifierDownload") else { return [] }
            guard id.hasSuffix("InNewWindow") else { return [item] }
            let tab = relay(item, item.title.replacingOccurrences(of: "New Window", with: "New Tab"), .tab)
            return id == "WKMenuItemIdentifierOpenLinkInNewWindow"
                ? [tab, relay(item, "Open Link to the Side", .side)] : [tab]
        }
    }

    private func relay(_ item: NSMenuItem, _ title: String, _ how: Opening) -> NSMenuItem {
        let relay = NSMenuItem(title: title, action: #selector(openLink), keyEquivalent: "")
        relay.target = self
        relay.representedObject = item
        relay.tag = how == .side ? 1 : 0
        return relay
    }

    @objc private func openLink(_ relay: NSMenuItem) {
        guard let item = relay.representedObject as? NSMenuItem, let action = item.action else { return }
        opens = relay.tag == 1 ? .side : .tab
        NSApp.sendAction(action, to: item.target, from: item)
    }

    /// A pick WebKit never asked a window for (New Tab on a `mailto:` link) must not make the page's next popup a tab
    /// (also from a key, `keyDown`).
    override func mouseDown(with event: NSEvent) {
        opens = nil
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        opens = nil
        if onKey?(event) != true {
            super.keyDown(with: event)
        }
    }

    /// A picture was taken (the registry counts it under its cap).
    var pictured: (() -> Void)?

    /// At 1x (6 MB for a full-window card on Retina, not 24): a tile is scaled down, a card shows it while loading.
    /// About 8 ms in WebKit's process, also out of a window.
    func takePicture(then taken: ((CGImage) -> Void)? = nil) {
        guard !bounds.isEmpty, url != nil else { return }
        let configuration = WKSnapshotConfiguration()
        // In points: the image comes at the screen's scale.
        configuration.snapshotWidth = NSNumber(value: bounds.width / ((window?.screen ?? NSScreen.main)?
                .backingScaleFactor ?? 2))
        takeSnapshot(with: configuration) { [weak self] image, _ in
            if let image = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                self?.shot.image = image
                self?.pictured?()
                taken?(image)
            }
        }
    }

    /// WebKit claims every drag over the page, whatever it carries (WKWebView's `_hitTest:dragTypes:`), so a card's
    /// drop zones would never hear of a pane dragged over it. The app's own drags go on to them; WebKit decides the
    /// rest (files, text), so a page can take an upload.
    @objc(_hitTest:dragTypes:) private func hitTest(_ point: UnsafeMutablePointer<NSPoint>,
                                                    dragTypes types: NSSet?) -> NSView?
    {
        guard let hit = Self.webKitHit, types?.contains(UTType.ovviDrag.identifier) != true else { return nil }
        return hit(self, Self.dragHit, point, types)
    }

    private static let dragHit = NSSelectorFromString("_hitTest:dragTypes:")
    private typealias DragHit = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSPoint>, NSSet?) -> NSView?
    /// WebKit's own answer (NSView's, if WebKit stops overriding it). A private method: if its shape ever changes,
    /// nil, so a drag reaches the card's drop zones and never the page, instead of reading a wrong argument.
    private static let webKitHit: DragHit? = {
        guard let method = class_getInstanceMethod(WKWebView.self, dragHit),
              let types = method_getTypeEncoding(method), String(cString: types) == "@32@0:8^{CGPoint=dd}16@24"
        else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: DragHit.self)
    }()

    func dropClaim() {
        wantsKeyboard = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsKeyboard, window != nil {
            takeKeyboard()
        }
    }

    override var acceptsFirstResponder: Bool {
        !inTile && super.acceptsFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onKeyboard?()
        }
        return became
    }
}
