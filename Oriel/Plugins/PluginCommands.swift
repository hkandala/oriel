import HerdrKit
import SwiftUI
import WebKit

extension CommandList {
    /// A plugin card's (future-work/plugins/building#debug-it): Reload Plugin and the Web Inspector, in the card's
    /// menu, View ▸ Pane and ⌘K.
    static func pluginCard(_ plugin: Plugin?) -> [Command] {
        guard let plugin else { return [] }
        let id = plugin.manifest.id, view = plugin.web.view
        return [
            Command(section: .pane, title: "Reload Plugin", key: .init("r", modifiers: [.command, .option]),
                    symbol: "arrow.clockwise", keywords: "plugin build refresh") { Task { await Plugin.reload(id) } },
            Command(section: .pane, title: view.inspectorShown ? "Hide Web Inspector" : "Show Web Inspector",
                    symbol: "hammer", keywords: "plugin developer tools devtools console",
                    action: view.toggleInspector),
        ]
    }

    /// ⌘K's: every plugin read and built again.
    static let reloadPlugins = Command(section: .palette, title: "Reload Plugins", symbol: "arrow.clockwise",
                                       keywords: "plugin build refresh packages") { Task { await Plugin.reloadAll() } }
}

extension WKWebView {
    /// WebKit's `_WKInspector`: no public API shows it (cmux ships it).
    var inspector: NSObject? {
        let selector = NSSelectorFromString("_inspector")
        return responds(to: selector) ? perform(selector)?.takeUnretainedValue() as? NSObject : nil
    }

    var inspectorShown: Bool {
        // KVC on a name WebKit dropped would throw.
        guard let inspector, inspector.responds(to: NSSelectorFromString("isVisible")) else { return false }
        return inspector.value(forKey: "visible") as? Bool == true
    }

    func toggleInspector() {
        if inspectorShown {
            inspector?.perform(NSSelectorFromString("close"))
        } else {
            showInspector()
        }
    }

    /// Web Inspector, docked under the page; its own control moves it to a window.
    func showInspector() {
        let show = NSSelectorFromString("show")
        guard let inspector, inspector.responds(to: show) else { return }
        // Docked each time: WebKit keeps the last choice of a window in the app's defaults.
        // ponytail: WebKit's private key; if it changes, the inspector opens as it was left.
        UserDefaults.standard.removeObject(forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
        inspector.perform(show)
    }
}
