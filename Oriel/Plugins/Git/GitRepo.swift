import AppKit
import HerdrKit
import SwiftUI

/// The Git home's data and writes: the checkout's branch, its changes, its branches and the history of every branch,
/// read again after each change in the work tree and after each write. Row 2 (`GitBar`) draws the branch and its
/// buttons natively; the page (`web/src/git.ts`) asks for the rest with `repo` and gets each new state.
@MainActor @Observable
final class GitRepo {
    @ObservationIgnored private weak var card: WebCard?
    private(set) var status: GitStatus?
    private(set) var branches: [Git.Branch] = []
    /// git's error when the root is no repository (or git cannot run); nil once a read worked.
    private(set) var failure: String?
    /// The write that runs, for its button's spinner: `fetch`, `pull`, `push`, `switch` or `commit`.
    private(set) var running: String?
    /// The page's part, as sent to it last.
    @ObservationIgnored private var state: [String: Any]?
    /// Writes run one at a time, in order (git takes `index.lock`); each waits for the one before it.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var again = false

    init(card: WebCard) {
        self.card = card
    }

    var root: String {
        card?.diff.root ?? ""
    }

    /// The card's machine, nil once the card is gone or git cannot run on it.
    private func exec() async -> (any Exec)? {
        guard let store = card?.store else { return nil }
        guard await store.gitRuns() else {
            failure = "git is not installed"
            return nil
        }
        return await store.machine.exec()
    }

    /// Reads everything again and sends the page what changed; a call during a read reads once more after it.
    func load() async {
        guard !reading else {
            again = true
            return
        }
        reading = true
        defer { reading = false }
        repeat {
            again = false
            guard let exec = await exec() else { return }
            let root = root
            async let status = GitStatus.of(root, exec: exec)
            async let changes = Git.changes(root, exec: exec)
            async let branches = Git.branches(root, exec: exec)
            async let log = Git.log(root, exec: exec)
            var state: [String: Any] = [:]
            do {
                let changes = try await changes
                state["staged"] = changes.staged.map(Self.json)
                state["unstaged"] = changes.unstaged.map(Self.json)
                set(\.failure, nil)
            } catch {
                state["failure"] = error.localizedDescription
                set(\.failure, error.localizedDescription)
            }
            await set(\.status, status)
            await set(\.branches, (try? branches) ?? [])
            // None before the first commit.
            let commits = await (try? log) ?? []
            state["commits"] = zip(commits, Git.graph(commits)).map { commit, row in
                ["hash": commit.hash, "subject": commit.subject, "author": commit.author,
                 "date": commit.date.timeIntervalSince1970 * 1000, "refs": commit.refs, "lane": row.lane,
                 "children": row.children, "parents": row.parents, "through": row.through] as [String: Any]
            }
            state["root"] = root
            if (self.state as NSDictionary?) != state as NSDictionary {
                self.state = state
                card?.send(["op": "repo", "repo": state])
            }
        } while again
    }

    private static func json(_ change: Git.Change) -> [String: Any] {
        ["letter": String(change.letter), "path": change.path, "oldPath": change.oldPath ?? NSNull()]
    }

    /// Observation tells the views of every write, also one that changes nothing.
    private func set<Value: Equatable>(_ path: ReferenceWritableKeyPath<GitRepo, Value>, _ value: Value) {
        if self[keyPath: path] != value {
            self[keyPath: path] = value
        }
    }

    /// While the card shows: reads again after each change under the root (on This Mac also `.git`'s own: a commit or
    /// a fetch from the terminal).
    func watch() async {
        await load()
        guard let store = card?.store else { return }
        let exec = await store.machine.exec()
        for await _ in Files.watch(root, exec: exec) {
            await load()
        }
    }

    /// The page's `repo` asks: `read` (the state, and the symbols its rows draw), and its writes, which answer once
    /// done (a failure shows git's message in the toast and answers an error).
    func answer(_ message: [String: Any]) async -> (Any?, String?) {
        let path = message["path"] as? String, old = message["oldPath"] as? String
        let paths = ["--"] + [path, old].compactMap(\.self)
        let done: Bool
        switch message["do"] as? String {
        case "read":
            if state == nil {
                await load()
            }
            return (["repo": state ?? ["failure": failure ?? "Not read"], "symbols": Self.symbols], nil)
        case "stage" where path != nil: done = await run(["add", "-A"] + paths)
        // Also before the first commit, where `restore --staged` finds no HEAD.
        case "unstage" where path != nil: done = await run(["reset", "-q"] + paths)
        case "stageAll": done = await run(["add", "-A"])
        case "unstageAll": done = await run(["reset", "-q"])
        case "commit":
            let text = (message["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return (nil, "No message") }
            done = await run(["commit", "-m", text], busy: "commit")
        default: return (nil, "Unknown message")
        }
        return done ? (true, nil) : (nil, "Failed")
    }

    func fetch() {
        Task { await run(["fetch", "--all"], busy: "fetch") }
    }

    /// git's own way (the user's `pull.rebase`); diverged branches with no setting fail with git's message.
    func pull() {
        Task { await run(["pull"], busy: "pull") }
    }

    /// A branch with no upstream is published to `origin` under its name.
    func push() {
        Task {
            guard let exec = await exec() else { return }
            let upstream = try? await Git.run(root, ["rev-parse", "--abbrev-ref", "@{upstream}"], exec: exec)
            await run(upstream != nil ? ["push"] : ["push", "-u", "origin", "HEAD"], busy: "push")
        }
    }

    /// A remote branch makes a local one that tracks it.
    func switchTo(_ branch: Git.Branch) {
        guard !branch.current, !branch.name.hasPrefix("-") else { return }
        Task { await run(["switch"] + (branch.remote ? ["--track", branch.name] : [branch.name]), busy: "switch") }
    }

    /// After the writes before it, then a read; a failure shows git's message in the card's toast. The network's may
    /// take long.
    @discardableResult
    private func run(_ arguments: [String], busy: String? = nil) async -> Bool {
        let previous = queue
        let write = Task { [weak self] () -> Bool in
            await previous?.value
            guard let self, let exec = await exec() else { return false }
            running = busy
            defer { running = nil }
            do {
                try await Git.run(root, arguments, timeout: .seconds(busy == nil ? 30 : 120), exec: exec)
                return true
            } catch {
                show(error.localizedDescription)
                return false
            }
        }
        queue = Task { _ = await write.value }
        let done = await write.value
        await load()
        return done
    }

    private func show(_ error: String) {
        let text = error.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        card?.toast = Toast(text: text, other: ("Copy", {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(error, forType: .string)
        }), main: ("OK", {}))
    }

    /// The SF Symbols the page's rows draw, as PNG data URLs it uses as masks in the text's color.
    private static let symbols: [String: String] = Dictionary(uniqueKeysWithValues: [
        "doc", "plus", "minus", "arrow.triangle.branch", "cloud", "tag",
    ].compactMap { name in
        let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration), let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return (name, "data:image/png;base64," + png.base64EncodedString())
    })
}
