import HerdrKit
import SwiftUI

/// ponytail: the web host's test card, keyed by terminal id alone, its cards kept until the app quits: a pane labeled
/// `oriel:webtest#<iid> <path>` shows `web/src/test.ts`. Phase 42's integration deletes this file once its plugin
/// cards hold a `WebCard`.
@MainActor private var cards: [String: WebCard] = [:]

extension Page {
    func webTest(_ pane: HostStore.Pane) -> WebCard? {
        guard let id = pane.terminalID, let label = PaneLabel(pane.label), label.plugin == "webtest" else { return nil }
        if let card = cards[id] {
            return card
        }
        let card = WebCard(kind: "test", arg: label.arg, store: store)
        card.view.onKeyboard = { [weak self] in self?.tookKeyboard(id) }
        card.view.setAccessibilityIdentifier("webtest.\(pane.id).page")
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
