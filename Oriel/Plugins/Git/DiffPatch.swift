import Foundation
import HerdrKit

extension WebCard {
    /// The diff page's ask: the pane's patch as git prints it (the page parses it), its repo's root, and row 2's
    /// state.
    func patch() async -> (Any?, String?) {
        guard let store else { return (nil, "Closed") }
        // The home shows no page.
        guard let source = diff.source else { return (nil, "No diff") }
        let root = diff.root
        guard await store.gitRuns() else { return (nil, "git is not installed") }
        do {
            let patch = try await Git.patch(root, commit: source == "uncommitted" ? nil : source,
                                            exec: store.machine.exec())
            return (["patch": patch, "root": root, "split": split, "list": list], nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
