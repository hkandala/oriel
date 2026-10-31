import HerdrKit
import SwiftUI

extension Page {
    /// The pane's browser or plugin card. Not made while the strip moves (making a web view took a frame), but where it
    /// rests (`stripMoving`, false again also when the strip goes mid-scroll).
    func cards(_ pane: HostStore.Pane?) -> (Browser?, Plugin?) {
        guard stripMoving else { return (pane.flatMap(browser), pane.flatMap(plugin)) }
        return (pane?.terminalID.flatMap(terminals.built), pane?.terminalID.flatMap(terminals.builtPlugin))
    }

    /// A browser's, a plugin's or an agent's card has a second header row; a terminal's, a floated or a choosing one
    /// has one.
    func twoRows(_ pane: HostStore.Pane?) -> Bool {
        guard let pane, !floats(pane), store.chooser(pane.id) == nil else { return false }
        return pane.plugin != nil || pane.agent != nil || ChatAdapters.recognize(pane.program) != nil
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
/// layers at its place (`cacheDisplay` drew SwiftUI's content blank).
struct ChatProbe: NSViewRepresentable {
    let terminalID: String
    let registry: PaneViewRegistry

    func makeNSView(context _: Context) -> NSView {
        let probe = NSView()
        registry.chatViews[terminalID] = { [weak probe] in
            guard let probe, let root = probe.window?.contentView?.superview?.layer, !probe.bounds.isEmpty,
                  let scale = probe.window?.backingScaleFactor else { return nil }
            let rect = probe.convert(probe.bounds, to: nil)
            let size = CGSize(width: rect.width * scale, height: rect.height * scale)
            guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            root.render(in: context)
            return context.makeImage()
        }
        return probe
    }

    func updateNSView(_: NSView, context _: Context) {}
}
