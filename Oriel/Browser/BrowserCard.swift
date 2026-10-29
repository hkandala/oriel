import HerdrKit
import SwiftUI
import WebKit

extension Page {
    /// A browser pane's card, made on first use.
    func browser(_ pane: HostStore.Pane) -> Browser? {
        guard let terminalID = pane.terminalID, let label = pane.browser else { return nil }
        return terminals.browser(pane, label, terminalID: terminalID, store: store)
    }

    /// A browser pane's page: its title, else its host, else its address; nil before it has one. Made no card: menus
    /// ask for every tab's title.
    func browserTitle(_ pane: HostStore.Pane, _ label: PaneLabel) -> String? {
        let browser = pane.terminalID.flatMap(terminals.built)
        let address = browser?.address ?? label.arg
        return browser.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? URL(string: address)?.host
            ?? (address.isEmpty ? nil : address)
    }
}

extension CommandList {
    /// A browser card's (ui/browser#commands-on-a-browser-card), in the main and the floating windows.
    static func browser(_ browser: Browser?) -> [Command] {
        [
            Command(section: .view, title: "Reload Page", key: .init("r"), symbol: "arrow.clockwise",
                    keywords: "refresh browser", enabled: browser?.loaded == true) { browser?.reload() },
            Command(section: .edit, title: "Open Location", key: .init("l"), symbol: "link",
                    keywords: "address url browser", enabled: browser != nil) { browser?.wantsAddress = true },
            Command(section: .edit, title: "Show Web Inspector", key: .init("i", modifiers: [.command, .option]),
                    symbol: "hammer", keywords: "developer tools devtools browser",
                    enabled: browser?.loaded == true) { browser?.showInspector() },
        ]
    }
}

/// The card's page (ui/browser#the-card): the web view inset 6 pt, a progress line under the header while
/// a page loads, a failure or "Open ‹url›?" in the middle, and the loader until the first page drew.
struct BrowserCard: View {
    let browser: Browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WebHost(view: browser.view)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding([.horizontal, .bottom], 6)
            // An empty web view draws white: hidden until it has a page.
            .opacity(browser.ready && browser.failure == nil && browser.asking == nil && browser.loaded ? 1 : 0)
            .overlay(alignment: .top) {
                if browser.loading {
                    ProgressView(value: browser.progress).progressViewStyle(.linear).tint(.accentColor)
                        .frame(height: 2).scaleEffect(y: 0.5)
                }
            }
            .overlay {
                if let failure = browser.failure {
                    failed(failure.text, hint: failure.hint)
                } else if let url = browser.asking {
                    Asking(browser: browser, url: url)
                } else if !browser.ready {
                    BrowserLoader()
                } else if !browser.loaded {
                    // No page yet: the kind's symbol; a click gives the address field the keyboard.
                    Image(systemName: "globe").font(.system(size: 44, weight: .light)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
                        .onTapGesture { browser.wantsAddress = true }
                        .accessibilityIdentifier("browser.\(browser.paneID).empty")
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

    /// A load that failed, in the app's words, and Reload.
    private func failed(_ text: String, hint: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 14)).multilineTextAlignment(.center).lineLimit(3)
                .accessibilityIdentifier("browser.\(browser.paneID).message")
            if let hint {
                Text(hint).foregroundStyle(.secondary)
            }
            Button("Reload", action: browser.reload).buttonStyle(.glassProminent).padding(.top, 4)
                .accessibilityIdentifier("browser.\(browser.paneID).retry")
        }
        .padding(24)
    }
}

/// A page the machine put in the label or the state file, from an origin not approved yet
/// (ui/browser#when-a-page-loads-by-itself): the question, its address, Open (Return) and Not Now (Esc).
private struct Asking: View {
    let browser: Browser
    let url: URL

    var body: some View {
        let id = "browser.\(browser.paneID)"
        VStack(spacing: 10) {
            Image(systemName: "globe").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text("Open this page?").font(.system(size: 15, weight: .semibold))
            addressText(url.absoluteString)
                .font(.system(size: 13)).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .accessibilityIdentifier("\(id).message")
            HStack(spacing: 8) {
                Button("Not Now", action: browser.notNow).buttonStyle(.glass)
                    .accessibilityIdentifier("\(id).not-now")
                Button("Open", action: browser.open).buttonStyle(.glassProminent)
                    .accessibilityIdentifier("\(id).open")
            }
            .controlSize(.large)
            .padding(.top, 6)
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

/// The card header's second row: Back, Forward, Reload or Stop, and the address field, which takes the free width;
/// then Web Inspector.
struct BrowserToolbar: View {
    let browser: Browser
    let page: Page
    @State private var text = ""
    @FocusState private var editing: Bool
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        let id = "browser.\(browser.paneID)"
        // The card buttons' one color; a button that cannot act dims as any disabled card button.
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.left", help: "Back", size: 22) { browser.view.goBack() }
                    .disabled(!browser.canGoBack)
                    .accessibilityIdentifier("\(id).back")
                IconButton(symbol: "chevron.right", help: "Forward", size: 22) { browser.view.goForward() }
                    .disabled(!browser.canGoForward)
                    .accessibilityIdentifier("\(id).forward")
                IconButton(symbol: browser.loading ? "xmark" : "arrow.clockwise", help: browser.loading ? "Stop"
                    : "Reload", size: 22) { browser.loading ? browser.view.stopLoading() : browser.reload() }
                    .disabled(!browser.loaded)
                    .accessibilityIdentifier("\(id).reload")
            }
            .foregroundStyle(look.paneButton)
            address(id)
            IconButton(symbol: "hammer", help: "Web Inspector", key: .init("i", modifiers: [.command, .option]),
                       size: 22, action: browser.showInspector)
                .disabled(!browser.loaded)
                .foregroundStyle(look.paneButton)
                .accessibilityIdentifier("\(id).inspector")
        }
    }

    /// A capsule: the host in full and the rest at half while not editing; a click or ⌘L selects it all. Return
    /// loads, Esc puts the address back; both give the keyboard to the page.
    private func address(_ id: String) -> some View {
        TextField("Enter a URL", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($editing)
            // On the field, before the overlay that would take it too.
            .accessibilityIdentifier("\(id).address")
            // Its text hidden under the shown address while not editing; not by opacity: SwiftUI focuses no view at
            // opacity 0.
            .foregroundStyle(editing ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
            .overlay(alignment: .leading) {
                // A click selects the address, as ⌘L does.
                if !editing {
                    shown.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(.rect)
                        .onTapGesture { editing = true }
                }
            }
            // A remote machine's name: its `localhost` is that machine's.
            .safeAreaInset(edge: .trailing, spacing: 4) {
                if browser.alias != nil {
                    machine.accessibilityIdentifier("\(id).machine")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, browser.alias == nil ? 10 : 4)
            .frame(minWidth: 120, maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            // A click puts the caret in it: the text cursor, and a little more fill, on hover.
            .background(Capsule().fill(.primary.opacity(hovering && !editing ? 0.1 : 0.06)))
            .pointerStyle(.horizontalText).onHover { hovering = $0 }
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
                // To the field's editor only: sent to the first responder, a web view that took the keyboard meanwhile
                // selected its whole page (a floated card).
                DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil) }
            }
            .onChange(of: browser.wantsAddress, initial: true) {
                guard browser.wantsAddress else { return }
                browser.wantsAddress = false
                focus(tries: 10)
            }
    }

    private var machine: some View {
        Text(page.store.machine.name).font(.system(size: 11)).foregroundStyle(look.needsYou).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(look.needsYou.opacity(0.18)))
            .fixedSize()
    }

    /// From the next turn (a first responder set during an update is undone), again every 50 ms while a card just
    /// made is not in its window yet, as long as it is still this card's turn.
    private func focus(tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 10 ? 0 : 0.05)) {
            guard !editing, tries > 0, let pane = page.store.pane(browser.paneID),
                  page.floats(pane) || page.keyboardCard(pane.tabID) === pane else { return }
            editing = true
            focus(tries: tries - 1)
        }
    }

    /// The address, or the prompt while there is none.
    private var shown: some View {
        // The field's own prompt is hidden with its text.
        Group {
            if browser.address.isEmpty {
                Text("Enter a URL").foregroundStyle(.tertiary)
            } else {
                addressText(browser.address)
            }
        }
        .font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
    }
}

/// An address as the toolbar and "Open this page?" show it: "localhost:3000" in full, "/dashboard" at half.
private func addressText(_ address: String) -> Text {
    let url = URL(string: address)
    let host = url.flatMap { url in url.host.map { $0 + (url.port.map { ":\($0)" } ?? "") } }
    let rest = host.map { address.components(separatedBy: $0).dropFirst().joined(separator: $0) } ?? ""
    return Text("\(Text(host ?? address))\(Text(rest).foregroundStyle(.secondary))")
}

/// Row 1's icon: the page's, else the globe.
struct BrowserIcon: View {
    let browser: Browser

    var body: some View {
        if let icon = browser.icon?.image {
            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                .frame(width: 16, height: 16).accessibilityHidden(true)
        } else {
            ProgramGlyph(icon: "globe")
        }
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
