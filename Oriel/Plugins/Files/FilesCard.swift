import HerdrKit
import SwiftUI

/// The Files card's second row: the filter, which the page runs over every path of the root, and Collapse All.
struct FilesBar: View {
    @Bindable var card: WebCard
    let paneID: String

    var body: some View {
        HStack(spacing: 6) {
            FilterField(prompt: "Filter", text: $card.filter, identifier: "pane.\(paneID).filter")
            Button {
                card.send(["op": "collapse"])
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.borderless)
            .help("Collapse All")
            .accessibilityLabel("Collapse All")
            .accessibilityIdentifier("pane.\(paneID).collapse")
        }
        .onChange(of: card.filter) { card.send(["op": "filter", "text": card.filter]) }
    }
}

extension WebCard {
    /// The Files page's asks (`web/src/files.ts`), from the root in the card's argument: a folder's entries, every
    /// path for the filter, and the repository's changes and history when the root is a repository's; and its report
    /// that the filter ended. The other kinds' messages come first (`answer`).
    func files(_ message: [String: Any]) async -> (Any?, String?) {
        let ask = message["op"] as? String
        guard ask != "filter" else {
            filter = message["text"] as? String ?? ""
            return (nil, nil)
        }
        guard ["list", "paths", "git"].contains(ask) else { return (nil, "Unknown message") }
        guard let exec = await store?.machine.exec() else { return (nil, "Closed") }
        do {
            switch ask {
            case "list":
                let entries = try await Files.list(message["path"] as? String ?? arg, repo: repo, exec: exec)
                return (entries.map { ["name": $0.name, "folder": $0.isFolder, "ignored": $0.ignored] }, nil)
            case "paths":
                return try await (Files.paths(arg, repo: repo, exec: exec), nil)
            default:
                // A root inside a repository but not its root shows no git (the Files pane's root is the repo's).
                let runs = await store?.gitRuns() == true
                repo = runs ? await Git.root(arg, exec: exec).flatMap { $0 == arg ? $0 : nil } : nil
                guard repo != nil else { return (NSNull(), nil) }
                async let changes = Git.status(arg, exec: exec)
                // None before the first commit.
                let commits = await (try? Git.log(arg, exec: exec)) ?? []
                let history = zip(commits, Git.graph(commits)).map { commit, row in
                    ["hash": commit.hash, "subject": commit.subject, "date": commit.date.timeIntervalSince1970 * 1000,
                     "lane": row.lane, "children": row.children, "parents": row.parents,
                     "through": row.through] as [String: Any]
                }
                return try await (["changes": changes.map { ["letter": String($0.letter), "path": $0.path] },
                                   "commits": history], nil)
            }
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
