import HerdrKit
import SwiftUI

/// A diff card's state, on its `Plugin`, so a float or another page keeps it: the patch of the label's source, the
/// layout, the file list and the files viewed or folded.
@MainActor @Observable
final class DiffCard {
    private(set) var files: [DiffFile] = []
    /// The last 50 commits, for the source pop-up.
    private(set) var commits: [Git.Commit] = []
    private(set) var failure: String?
    private(set) var loaded = false
    var sideBySide = false {
        didSet { redraw() }
    }

    var showsList = true
    /// The file at the top of the diff, lit in the list.
    var current = 0
    /// Viewed files, as they were when marked: one that changes since is not viewed any more.
    private(set) var viewed: [String: DiffFile] = [:]
    private(set) var folded: Set<String> = []
    @ObservationIgnored let view = DiffView()
    @ObservationIgnored private var look = Look(style: .glass, dark: true)
    @ObservationIgnored private var root = ""
    @ObservationIgnored private weak var page: Page?
    @ObservationIgnored private weak var plugin: Plugin?

    init() {
        view.onCurrent = { [weak self] in self?.current = $0 }
        view.header = { [weak self] file in
            guard let self else { return NSView() }
            return NSHostingView(rootView: DiffHeader(card: self, paneID: plugin?.paneID ?? "", file: file)
                .environment(\.look, look))
        }
        for text in view.texts {
            text.onOpen = { [weak self] row in
                guard let self, files.indices.contains(row.file) else { return }
                open(files[row.file], line: row.line)
            }
            text.onKeyboard = { [weak self] in
                if let self, let plugin {
                    page?.terminals.claimed(plugin.terminalID)
                }
            }
        }
    }

    /// The label's source; again on each change under the root while it is Uncommitted and the card shows.
    /// ponytail: a whole `git diff` per change (a build's writes run it each second); compare `--numstat` first
    /// when that costs.
    func load(_ plugin: Plugin, page: Page) async {
        (self.page, self.plugin) = (page, plugin)
        let (root, source) = plugin.label.diff, exec = await page.store.machine.exec()
        self.root = root
        guard await page.store.gitRuns() else {
            failure = "Git is not installed on this Mac"
            return
        }
        // git diff runs, and finds nothing, outside a repository too.
        // ponytail: a machine that does not answer reads as no repository too, until the card shows again.
        guard await Git.root(root, exec: exec) != nil else {
            failure = "Not a Git repository"
            return
        }
        var changes = source == "uncommitted" ? Files.watch(root, exec: exec).makeAsyncIterator() : nil
        repeat {
            async let log = try? Git.log(root, exec: exec)
            do {
                let files = try await Git.diff(root, commit: source == "uncommitted" ? nil : source, exec: exec)
                guard !Task.isCancelled else { return }
                failure = nil
                if files != self.files || !loaded {
                    let stale = viewed.filter { !files.contains($0.value) }.keys
                    viewed = viewed.filter { files.contains($0.value) }
                    folded.subtract(stale)
                    // A big file starts folded: the whole text is laid out at once (`DiffText.show`).
                    // ponytail: by file; many mid-size files still lay out together.
                    let known = Set(self.files.map(\.path))
                    folded.formUnion(files.filter { !known.contains($0.path) && $0.added + $0.removed > 2000 }
                        .map(\.path))
                    self.files = files
                    redraw()
                }
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
                files = []
                redraw()
            }
            commits = await Array((log ?? []).prefix(50))
            loaded = true
            if let place = plugin.place, let file = files.firstIndex(where: { $0.path == place }) {
                view.reveal(file)
            }
            plugin.place = nil
        } while await changes?.next() != nil && !Task.isCancelled
    }

    /// From the host's update: the redraw writes `current`, not during it.
    func restyle(_ look: Look) {
        guard look != self.look else { return }
        self.look = look
        DispatchQueue.main.async { self.redraw() }
    }

    func fold(_ file: Int) {
        let path = files[file].path
        if folded.remove(path) == nil {
            folded.insert(path)
        }
        redraw(anchor: path)
    }

    /// Viewed folds the file; not viewed opens it again.
    func markViewed(_ file: Int, _ seen: Bool) {
        let path = files[file].path
        viewed[path] = seen ? files[file] : nil
        if seen {
            folded.insert(path)
        } else {
            folded.remove(path)
        }
        redraw(anchor: path)
    }

    func isViewed(_ file: DiffFile) -> Bool {
        viewed[file.path] == file
    }

    /// The file's plugin in a new tab, at `line`.
    func open(_ file: DiffFile, line: Int? = nil) {
        let path = (root as NSString).appendingPathComponent(file.path)
        Task { await page?.open(.opening(path), arg: path, at: line.map(String.init), from: plugin?.terminalID ?? "") }
    }

    private func redraw(anchor: String? = nil) {
        view.show(files, folded: folded, sideBySide: sideBySide, look: look, anchor: anchor)
    }
}
