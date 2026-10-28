import AppKit
import WebKit

/// The web view, which takes the keyboard as a terminal does (`PaneSurfaceView`): now, or once it is in a window.
final class BrowserView: WKWebView {
    var onKeyboard: (() -> Void)?
    /// A key the card takes before the page (its "Open this page?").
    var onKey: ((NSEvent) -> Bool)?
    private var wantsKeyboard = false

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

    override func keyDown(with event: NSEvent) {
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
