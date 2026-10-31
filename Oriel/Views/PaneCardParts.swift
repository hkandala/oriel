import HerdrKit
import SwiftUI

extension Page {
    /// The pane's browser or plugin card. Made only in the selected tab (or floated) and not while the strip moves
    /// (making a web view took a frame; `stripMoving` is false again also when the strip goes mid-scroll): a neighbor
    /// page the lazy strip lays out shows its last picture, and a card past the kept bound is not made again there.
    func cards(_ pane: HostStore.Pane?) -> (Browser?, Plugin?) {
        guard let pane, stripMoving || pane.tabID != selectedTab?.id && !floats(pane) else {
            return (pane.flatMap(browser), pane.flatMap(plugin))
        }
        return (pane.terminalID.flatMap(terminals.built), pane.terminalID.flatMap(terminals.builtPlugin))
    }

    /// A browser's, a plugin's or an agent's card has a second header row; a terminal's, a floated or a choosing one
    /// has one.
    func twoRows(_ pane: HostStore.Pane?) -> Bool {
        guard let pane, !floats(pane), store.chooser(pane.id) == nil else { return false }
        // Only a plugin with pages has controls, a user's only with a header or Back and Forward; a missing one none.
        guard let label = pane.plugin else { return pane.agent != nil || ChatAdapters.recognize(pane.program) != nil }
        return label.manifest.map { plugin in PluginPage(plugin.id, label.place).map(plugin.hasRow) ?? false } ?? false
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

    func makeNSView(context _: Context) -> NSView {
        let probe = NSView()
        registry.chatViews[terminalID] = { [weak probe] in
            // Not one already out of view: a blank picture would replace a good one.
            guard let probe, let root = probe.window?.contentView?.superview?.layer, !probe.visibleRect.isEmpty,
                  probe.window != nil else { return nil }
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
            while let next = layer.sublayers?.last(where: { !$0.isHidden && $0.frame.contains(area) }) {
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

    func updateNSView(_: NSView, context _: Context) {}
}
