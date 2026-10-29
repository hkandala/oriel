import AppKit
import SwiftUI

/// Sits under Edit's text view, which MarkdownEngine hands out to no one: it finds the view, and takes the clicks on
/// its links, which the engine would give the Mac's browser (a relative path as `https://path`).
@MainActor
final class EditorAnchor {
    fileprivate weak var view: NSView?
    /// A linked open's line, until the text view takes the keyboard.
    private var pending: Int?

    /// The text view with the keyboard, or under the anchor's middle (the outline is clicked on a card in view); only
    /// the one in the anchor's frame: a zoomed card may lie over it.
    var textView: NSTextView? {
        guard let view, let window = view.window else { return nil }
        let frame = view.convert(view.bounds, to: nil)
        let hit = window.contentView?.superview?.hitTest(NSPoint(x: frame.midX, y: frame.midY))
        let scroll = [window.firstResponder as? NSView, hit].lazy.compactMap { $0?.enclosingScrollView }.first {
            let mine = $0.convert($0.bounds, to: nil)
            return frame.contains(NSPoint(x: mine.midX, y: mine.midY))
        }
        return scroll?.documentView?.subviews.lazy.compactMap { $0 as? NSTextView }.first
    }

    /// Puts the caret at the offset and scrolls its line to the top; later when the text view is not found yet.
    func jump(to offset: Int) {
        guard let textView else {
            pending = offset
            return
        }
        guard let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset) else { return }
        let start = content.documentRange.location
        layout.ensureLayout(for: NSTextRange(location: start, end: location) ?? content.documentRange)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        if let fragment = layout.textLayoutFragment(for: location) {
            textView.scroll(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY))
        }
    }

    /// The text view took the keyboard: Find (⌘F) sends the text finder's actions to it; a pending jump runs.
    func tookKeyboard() {
        textView?.usesFindBar = true
        if let pending {
            self.pending = nil
            jump(to: pending)
        }
    }

    /// The text came from disk: undo would replay old ranges on it.
    func reloaded() {
        textView?.undoManager?.removeAllActions()
    }

    /// A click on a link in Edit puts the caret there: links open from Read.
    fileprivate func click(_ event: NSEvent) -> Bool {
        guard let view, let window = view.window, event.window === window,
              view.convert(view.bounds, to: nil).contains(event.locationInWindow), let textView,
              textView.isEditable,
              window.contentView?.superview?.hitTest(event.locationInWindow)?.isDescendant(of: textView) == true,
              let storage = textView.textStorage
        else { return false }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let index = textView.characterIndex(for: point)
        // The character nearest the point: on it, not beside a line that ends with a link.
        guard index != NSNotFound, index < storage.length,
              storage.attribute(.link, at: index, effectiveRange: nil) != nil,
              textView.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
                  .contains(point)
        else { return false }
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: index, length: 0))
        return true
    }
}

/// The anchor's view; it holds the link-click monitor while it is in a window.
struct AnchorView: NSViewRepresentable {
    let anchor: EditorAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = MonitorView()
        view.anchor = anchor
        anchor.view = view
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    final class MonitorView: NSView {
        var anchor: EditorAnchor?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                MainActor.assumeIsolated { self?.anchor?.click(event) == true } ? nil : event
            }
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
