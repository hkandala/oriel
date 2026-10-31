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

/// A web card's last picture where its page goes: a browser's page sits 6 pt in, with rounded corners; a plugin's
/// content as `PluginCard` places it.
struct WebPicture: View {
    let picture: CGImage
    let browser: Bool

    var body: some View {
        Image(decorative: picture, scale: 1).resizable()
            .clipShape(.rect(cornerRadius: browser ? 6 : 0))
            .padding([.horizontal, .bottom], browser ? 6 : PaneCard.inset)
    }
}
