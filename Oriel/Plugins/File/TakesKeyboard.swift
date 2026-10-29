import AppKit
import SwiftUI

extension View {
    /// A SwiftUI content takes the keyboard: on a click, and when the page gives it to the card.
    func takesKeyboard(_ plugin: Plugin, _ page: Page) -> some View {
        modifier(TakesKeyboard(plugin: plugin, page: page))
    }
}

private struct TakesKeyboard: ViewModifier {
    let plugin: Plugin
    let page: Page
    @FocusState private var focused: Bool
    /// False in an overview tile, which leaves the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .simultaneousGesture(TapGesture().onEnded { plugin.wantsKeyboard = true })
            .onChange(of: plugin.wantsKeyboard, initial: true) {
                if plugin.wantsKeyboard, isEnabled {
                    plugin.wantsKeyboard = false
                    Task { focused = true }
                }
            }
            .onChange(of: focused) {
                if focused {
                    page.terminals.claimed(plugin.terminalID)
                }
            }
    }
}

/// A click on a preview's AppKit view (a PDF, a player, an image), which SwiftUI's taps miss: the view takes the
/// keyboard itself, for its own keys (arrows, Space), and claims it for the card, so ⌘W closes the card. On the mouse
/// down: a PDF's selection loop takes the mouse up.
final class KeyboardClick: NSGestureRecognizer {
    private weak var plugin: Plugin?
    private weak var terminals: PaneViewRegistry?

    init(_ plugin: Plugin?, _ page: Page) {
        self.plugin = plugin
        terminals = page.terminals
        super.init(target: nil, action: nil)
        delaysPrimaryMouseButtonEvents = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func mouseDown(with _: NSEvent) {
        view?.window?.makeFirstResponder(view)
        if let plugin {
            terminals?.claimed(plugin.terminalID)
        }
        // The view gets the click as ever.
        state = .failed
    }
}

extension NSView {
    /// The view takes the keyboard the page gives the card (`wantsKeyboard`), on the next turn: a first responder set
    /// during an update is undone, and a host that adopts the view has it in its window by then.
    func takeKeyboard(_ plugin: Plugin?) {
        guard let plugin, plugin.wantsKeyboard else { return }
        plugin.wantsKeyboard = false
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }
}
