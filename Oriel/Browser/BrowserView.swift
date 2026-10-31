import AppKit
import WebKit

/// The web view, which takes the keyboard as a terminal does (`PaneSurfaceView`): now, or once it is in a window.
class BrowserView: WKWebView {
    var onKeyboard: (() -> Void)?
    /// A key the card takes before the page (its "Open this page?").
    var onKey: ((NSEvent) -> Bool)?
    private var wantsKeyboard = false
    /// Open ‹Link› in New Tab was picked: the page asks for its new window next (`createWebViewWith`).
    var opensTab = false
    /// In an overview's tile (D70): keys go to the overview; a claim waits until the card has it back.
    var inTile = false
    /// The page's last picture (`takePicture`): its overview tile, and over the page as it comes into view until
    /// WebKit drew it (`coverUntilDrawn`). Observed: a tile shows it as it comes.
    let shot = Shot()
    @MainActor @Observable final class Shot {
        var image: CGImage?
    }

    /// The picture over the page in its newest host (`WebHost`), until the page drew.
    weak var cover: NSView?
    private var coverWatch: NSKeyValueObservation?

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

    /// At 1x (6 MB for a full-window card on Retina, not 24): a cover shows a few frames and a tile is scaled down.
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
                taken?(image)
            }
        }
    }

    /// Its picture over it as it comes into view, until WebKit drew it: WebKit paints only what shows, so a page
    /// scrolled back into the strip's view or put back into a window drew blank for a frame or two. Not over a page
    /// that shows already (a swipe's landing), nor one of other proportions (resized meanwhile); a new web view (its
    /// card made again) takes it at any size. At most 2 s, also while a page loads.
    func coverUntilDrawn() {
        cover?.removeFromSuperview()
        guard let box = superview, let picture = shot.image, window == nil || visibleRect.isEmpty,
              bounds.isEmpty || abs(Double(picture.width) * bounds.height - Double(picture.height) * bounds.width)
              < bounds.width * 2 else { return }
        let cover = Cover(frame: frame)
        cover.autoresizingMask = [.width, .height]
        cover.wantsLayer = true
        cover.layer?.contents = picture
        cover.layer?.contentsGravity = .resize
        box.addSubview(cover)
        self.cover = cover
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak cover] in
            cover?.removeFromSuperview()
        }
        coverWatch = observe(\.isLoading) { view, _ in
            MainActor.assumeIsolated { view.uncover() }
        }
        uncover()
    }

    /// Once its page is loaded: after the next visible-rect update WebKit sends (as it comes into view), the next
    /// presentation update; at the latest 0.5 s after.
    /// ponytail: WebKit's SPI (its own tests use it); without it the cover goes after 100 ms, which can show a blank
    /// frame again.
    private func uncover() {
        guard let cover, !isLoading, url != nil else { return }
        coverWatch = nil
        let remove: @convention(block) () -> Void = { [weak cover] in cover?.removeFromSuperview() }
        let presented: @convention(block) () -> Void = { [weak self] in
            self?.perform(NSSelectorFromString("_doAfterNextPresentationUpdate:"), with: remove)
        }
        let shown = NSSelectorFromString("_doAfterNextVisibleContentRectUpdate:"), spi = responds(to: shown)
        if spi {
            perform(shown, with: presented)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (spi ? 0.5 : 0.1)) { [weak cover] in
            cover?.removeFromSuperview()
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

/// A web view's picture over it, which takes no clicks.
private final class Cover: NSView {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
