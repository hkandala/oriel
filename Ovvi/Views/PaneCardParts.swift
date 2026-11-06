import HerdrKit
import SwiftUI

extension Page {
    /// The pane's browser or plugin card, made on first use; `make` false: only one made before (a kept page out of
    /// view must not make again a card the registry dropped). ponytail: a hidden card holds a dropped card's web view
    /// until its next body, usually the next snapshot; make the registry observed if that wait matters.
    func cards(_ pane: HostStore.Pane?, make: Bool = true) -> (Browser?, Plugin?) {
        guard make else {
            let id = pane?.terminalID ?? ""
            return (terminals.built(id), terminals.builtPlugin(id))
        }
        return (pane.flatMap(browser), pane.flatMap(plugin))
    }

    /// A browser's, a plugin's or an agent's card has a second header row; a terminal's, a floated or a choosing one
    /// has one.
    func twoRows(_ pane: HostStore.Pane?) -> Bool {
        guard let pane, !floats(pane), store.chooser(pane.id) == nil else { return false }
        // The browser's toolbar (native: no entry); a plugin with pages has controls, a user's only with a header or
        // Back and Forward; a missing one none.
        guard let label = pane.plugin else { return pane.agent != nil || ChatAdapters.recognize(pane.program) != nil }
        return label.manifest.map { plugin in
            plugin.entry == nil || plugin.hasRow
        } ?? false
    }

    /// The keyboard goes to the previous or next card in the tab's tree, round the ends; not to a floated one.
    func stepCard(_ offset: Int) {
        guard let ids = selectedTab?.tree?.paneIDs.filter({ store.pane($0).map { !floats($0) } == true }),
              let from = keyboardPane,
              let index = ids.firstIndex(of: from.id),
              let pane = store.pane(ids[(index + offset + ids.count) % ids.count]) else { return }
        go(to: pane)
    }

    /// The chats of a tab that leaves view take their picture (their overview tile) before SwiftUI hides its kept
    /// page, which leaves them none to give (`ChatProbe`).
    func leaving(_ tabID: String?) {
        for id in store.panes(in: tabID).compactMap(\.terminalID) {
            if let picture = terminals.chatViews[id]?() {
                terminals.keep(id, picture)
            }
        }
    }

    /// The card's header: one row or two.
    func headerHeight(_ pane: HostStore.Pane?) -> CGFloat {
        PaneCard.header + (twoRows(pane) ? PaneCard.row : 0)
    }
}

/// A card's last picture where its content goes: a browser's page sits 6 pt in, with rounded corners; a plugin's
/// content as `PluginCard` places it; a chat's fills the card under its header.
struct CardPicture: View {
    let picture: CGImage
    let pane: HostStore.Pane

    var body: some View {
        let browser = pane.browser != nil, inset = browser ? 6 : pane.plugin != nil ? PaneCard.inset : 0
        Image(decorative: picture, scale: 1).resizable()
            .clipShape(.rect(cornerRadius: browser ? 6 : 0))
            .padding([.horizontal, .bottom], inset)
    }
}

/// Behind a chat's view in its card: the chat's picture as it leaves view (`PaneViewRegistry.show`), from the window's
/// layers at its place (`cacheDisplay` drew SwiftUI's content blank). ponytail: the deepest layer holding the place is
/// the rows' (the reply box is a sibling, so it is not in the picture); find SwiftUI's card layer if that matters.
struct ChatProbe: NSViewRepresentable {
    let terminalID: String
    let registry: PaneViewRegistry
    /// In a kept page out of view (as `TerminalHost`'s).
    let hidden: Bool

    func makeNSView(context _: Context) -> Probe {
        let probe = Probe()
        registry.chatViews[terminalID] = { [weak probe] in
            // Not one already out of view: a blank picture, or the page over it, would replace a good one.
            guard let probe, !probe.outOfView, let root = probe.window?.contentView?.superview?.layer,
                  !probe.visibleRect.isEmpty, probe.window != nil else { return nil }
            // At 1x, as web cards' pictures.
            let rect = probe.convert(probe.bounds, to: nil), scale = 1.0
            let size = CGSize(width: rect.width * scale, height: rect.height * scale)
            guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
            context.scaleBy(x: scale, y: scale)
            // The deepest layer that holds the chat's place (its rows, under 1 ms), not the window's (120 ms).
            var layer = root, area = rect
            while let next = layer.sublayers?
                .last(where: { !$0.isHidden && $0.opacity > 0 && $0.frame.contains(area) })
            {
                area = next.convert(area, from: layer)
                layer = next
            }
            if layer.contentsAreFlipped() {
                context.translateBy(x: -area.minX, y: area.maxY)
                context.scaleBy(x: 1, y: -1)
            } else {
                context.translateBy(x: -area.minX, y: -area.minY)
            }
            layer.render(in: context)
            return context.makeImage()
        }
        return probe
    }

    func updateNSView(_ probe: Probe, context _: Context) {
        probe.outOfView = hidden
    }

    final class Probe: NSView {
        /// In a kept page out of view (`TabPages`).
        var outOfView = false
    }
}

/// A floated pane's card in its tab, under its header: a line that says where the pane is, Show Window, which
/// brings its window to the front, and Bring Back Here, which detaches it into this card with the keyboard.
struct FloatedPlaceholder: View {
    let page: Page
    let pane: HostStore.Pane

    var body: some View {
        VStack(spacing: 12) {
            Text("This pane is open in a floating window.").foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pane.\(pane.id).floating")
            HStack(spacing: gap) {
                Button("Show Window") { page.float(pane) }
                    .accessibilityIdentifier("pane.\(pane.id).show")
                Button("Bring Back Here") {
                    if let terminalID = pane.terminalID {
                        page.floating[terminalID] = nil
                    }
                    page.go(to: pane)
                }
                .accessibilityIdentifier("pane.\(pane.id).back")
            }
            .buttonStyle(.glass)
        }
        .padding(gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
