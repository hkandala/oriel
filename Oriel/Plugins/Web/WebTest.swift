import HerdrKit
import SwiftUI

/// ponytail: the web host's test card until phase 42's plugin cards hold a `WebCard`: a pane labeled
/// `oriel:webtest#<iid> <path>` shows `web/src/test.ts`, and its cards stay until the app quits.
@MainActor private var cards: [String: WebCard] = [:]

extension Page {
    func webTest(_ pane: HostStore.Pane) -> WebCard? {
        guard let id = pane.terminalID, let label = PaneLabel(pane.label), label.plugin == "webtest" else { return nil }
        if let card = cards[id] {
            return card
        }
        let card = WebCard(kind: "test", arg: label.arg, store: store)
        card.view.onKeyboard = { [weak self] in self?.tookKeyboard(id) }
        cards[id] = card
        return card
    }
}

struct WebTestCard: View {
    let card: WebCard
    let paneID: String

    var body: some View {
        WebCardContent(card: card).testValue("webtest.\(paneID)", "Edited", card.dirty ? "dirty" : "clean")
    }
}
