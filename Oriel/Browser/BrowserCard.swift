import HerdrKit
import SwiftUI
import WebKit

extension Page {
    /// A browser pane's card, made on first use.
    func browser(_ pane: HostStore.Pane) -> Browser? {
        guard let terminalID = pane.terminalID, let label = pane.browser else { return nil }
        return terminals.browser(pane, label, terminalID: terminalID, store: store)
    }

    /// A browser pane's tab title: its page's title, else its host, else "New Tab". Made no card: menus ask for
    /// every tab's title.
    func browserTitle(_ pane: HostStore.Pane, _ label: PaneLabel) -> String {
        let browser = pane.terminalID.flatMap(terminals.built)
        let address = browser?.address ?? label.arg
        return browser.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? URL(string: address)?.host
            ?? (address.isEmpty ? "New Tab" : address)
    }
}

extension CommandList {
    /// A browser card's (future-work/web-page#commands-on-a-browser-card), in the main and the floating windows.
    static func browser(_ browser: Browser?) -> [Command] {
        [
            Command(section: .edit, title: "Open Location", key: .init("l"), symbol: "link",
                    keywords: "address url browser", enabled: browser != nil) { browser?.wantsAddress = true },
            Command(section: .edit, title: "Show Web Inspector", key: .init("i", modifiers: [.command, .option]),
                    symbol: "hammer", keywords: "developer tools devtools browser",
                    enabled: browser?.address.isEmpty == false) { browser?.showInspector() },
        ]
    }
}

/// The card's page (future-work/web-page#the-card): the web view inset 6 pt, a progress line under the header while
/// a page loads, a failure or "Open ‹url›?" in the middle, and the loader until the first page drew.
struct BrowserCard: View {
    let browser: Browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WebHost(view: browser.view)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding([.horizontal, .bottom], 6)
            .opacity(browser.ready && browser.failure == nil && browser.asking == nil ? 1 : 0)
            .overlay(alignment: .top) {
                if browser.loading {
                    ProgressView(value: browser.progress).progressViewStyle(.linear).tint(.accentColor)
                        .frame(height: 2).scaleEffect(y: 0.5)
                }
            }
            .overlay {
                if let failure = browser.failure {
                    message(failure.text, hint: failure.hint, symbol: "exclamationmark.triangle", button: "Reload",
                            action: browser.reload)
                } else if let url = browser.asking {
                    message("Open \(url.absoluteString)?", hint: nil, symbol: "globe", button: "Open",
                            action: browser.open)
                } else if !browser.ready {
                    BrowserLoader()
                }
            }
            .overlay {
                if let popup = browser.popup {
                    Popup(view: popup, title: browser.popupHost, close: browser.closePopup).padding(24)
                }
            }
            .animation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.15), value: browser.ready)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("browser.\(browser.paneID).card")
    }

    private func message(_ text: String, hint: String?, symbol: String, button: String,
                         action: @escaping () -> Void) -> some View
    {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 14)).multilineTextAlignment(.center).lineLimit(3)
                .accessibilityIdentifier("browser.\(browser.paneID).message")
            if let hint {
                Text(hint).foregroundStyle(.secondary)
            }
            Button(button, action: action).buttonStyle(.glassProminent).padding(.top, 4)
                .accessibilityIdentifier("browser.\(browser.paneID).\(button == "Reload" ? "retry" : "open")")
        }
        .padding(24)
    }
}

/// While a browser card is built: the `globe` symbol, and under it a spinner left of "Opening Browser…".
struct BrowserLoader: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe").font(.system(size: 28)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Opening Browser…").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Opening Browser")
    }
}

/// A `window.open` page over the card, with its title and a close button; `window.close()` closes it too.
private struct Popup: View {
    let view: WKWebView
    let title: String
    let close: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                IconButton(symbol: "xmark", help: "Close", size: 22, action: close)
            }
            .padding(.leading, 11).padding(.trailing, 6).frame(height: 32)
            WebHost(view: view)
        }
        .background(look.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 12)
    }
}

/// Shows a web view the registry owns; the newest host adopts it. A card out of view takes its web view out of the
/// window with it, and the web view lives on (hidden ones saw dropped events otherwise).
private struct WebHost: NSViewRepresentable {
    let view: WKWebView

    func makeNSView(context _: Context) -> NSView {
        let host = NSView()
        view.removeFromSuperview()
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        return host
    }

    func updateNSView(_: NSView, context _: Context) {}
}

/// The card header's toolbar (mock-up A): Back, Forward, Reload or Stop, and the address field, which takes the free
/// width; then Web Inspector.
struct BrowserToolbar: View {
    let browser: Browser
    let page: Page
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        let id = "browser.\(browser.paneID)"
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.left", help: "Back", size: 22) { browser.view.goBack() }
                    .disabled(!browser.canGoBack).opacity(browser.canGoBack ? 1 : 0.35)
                    .accessibilityIdentifier("\(id).back")
                IconButton(symbol: "chevron.right", help: "Forward", size: 22) { browser.view.goForward() }
                    .disabled(!browser.canGoForward).opacity(browser.canGoForward ? 1 : 0.35)
                    .accessibilityIdentifier("\(id).forward")
                IconButton(symbol: browser.loading ? "xmark" : "arrow.clockwise", help: browser.loading ? "Stop"
                    : "Reload", size: 22) { browser.loading ? browser.view.stopLoading() : browser.reload() }
                    .accessibilityIdentifier("\(id).reload")
            }
            address(id)
            IconButton(symbol: "hammer", help: "Web Inspector", key: .init("i", modifiers: [.command, .option]),
                       size: 22, action: browser.showInspector)
                .disabled(browser.address.isEmpty)
                .accessibilityIdentifier("\(id).inspector")
        }
    }

    /// A capsule: the host in full and the rest at half while not editing; a click or ⌘L selects it all. Return
    /// loads, Esc puts the address back; both give the keyboard to the page.
    private func address(_ id: String) -> some View {
        TextField("Address", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($editing)
            // On the field, before the overlay that would take it too.
            .accessibilityIdentifier("\(id).address")
            .opacity(editing ? 1 : 0)
            .overlay(alignment: .leading) {
                if !editing {
                    shown.allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 120, maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(Capsule().fill(.primary.opacity(0.06)))
            .overlay {
                Capsule().strokeBorder(editing ? Color.accentColor : .primary.opacity(0.08),
                                       lineWidth: editing ? 1.5 : 0.5)
            }
            .focusEffectDisabled()
            .onSubmit { browser.go(text) }
            .onExitCommand {
                text = browser.address
                browser.view.takeKeyboard()
            }
            .onChange(of: browser.address, initial: true) {
                if !editing {
                    text = browser.address
                }
            }
            .onChange(of: editing) {
                guard editing else {
                    text = browser.address
                    return
                }
                page.tookKeyboard(browser.terminalID)
                // Selected whole, after the field took the keyboard.
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
            .onChange(of: browser.wantsAddress, initial: true) {
                guard browser.wantsAddress else { return }
                browser.wantsAddress = false
                // On the next turn: a first responder set during an update is undone.
                DispatchQueue.main.async { editing = true }
            }
    }

    /// "localhost:3000" in full, "/dashboard" at half.
    private var shown: some View {
        let url = URL(string: browser.address)
        let host = url.flatMap { url in url.host.map { $0 + (url.port.map { ":\($0)" } ?? "") } }
        let rest = host.map { browser.address.components(separatedBy: $0).dropFirst().joined(separator: $0) } ?? ""
        return Text("\(Text(host ?? browser.address))\(Text(rest).foregroundStyle(.secondary))")
            .font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
    }
}

/// A floated browser pane: the toolbar without the card buttons, under the floating window's title row.
struct FloatingBrowser: View {
    let browser: Browser
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(browser: browser, page: page).padding(.horizontal, 11).frame(height: PaneCard.header)
            BrowserCard(browser: browser)
        }
        .onAppear { browser.takeKeyboard() }
    }
}
