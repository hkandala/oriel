import AppKit
import SwiftUI

extension View {
    /// A content that is no text view takes the keyboard, as phase 42's placeholder: on a click, and when the page
    /// gives it to the card.
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

/// A click on a preview's AppKit view, which SwiftUI's taps miss: the card takes the keyboard (`takesKeyboard`).
final class KeyboardClick: NSClickGestureRecognizer {
    private weak var plugin: Plugin?

    init(_ plugin: Plugin?) {
        self.plugin = plugin
        super.init(target: nil, action: nil)
        target = self
        action = #selector(clicked)
        delaysPrimaryMouseButtonEvents = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func clicked() {
        plugin?.wantsKeyboard = true
    }
}
