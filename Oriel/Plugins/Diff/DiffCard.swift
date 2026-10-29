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
        for text in view.texts {
            text.onOpen = { [weak self] row in
                guard let self, files.indices.contains(row.file) else { return }
                open(files[row.file], line: row.line)
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
        guard await gitUsable.value || page.store.machine.isRemote else {
            failure = "Git is not installed on this Mac"
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

    func restyle(_ look: Look) {
        guard (look.style, look.dark, look.contrast) != (self.look.style, self.look.dark, self.look.contrast)
        else { return }
        self.look = look
        redraw()
    }

    func fold(_ file: Int) {
        let path = files[file].path
        if folded.remove(path) == nil {
            folded.insert(path)
        }
        redraw(anchor: file)
    }

    /// Viewed folds the file; not viewed opens it again.
    func view(_ file: Int, _ seen: Bool) {
        let path = files[file].path
        viewed[path] = seen ? files[file] : nil
        if seen {
            folded.insert(path)
        } else {
            folded.remove(path)
        }
        redraw(anchor: file)
    }

    func isViewed(_ file: DiffFile) -> Bool {
        viewed[file.path] == file
    }

    /// The file's plugin in a new tab, at `line`.
    func open(_ file: DiffFile, line: Int? = nil) {
        let path = (root as NSString).appendingPathComponent(file.path)
        Task { await page?.open(.opening(path), arg: path, at: line.map(String.init)) }
    }

    private func redraw(anchor: Int? = nil) {
        view.header = { [weak self] file in
            guard let self, let plugin else { return NSView() }
            return NSHostingView(rootView: DiffHeader(card: self, plugin: plugin, file: file).environment(\.look, look))
        }
        view.show(files, folded: folded, sideBySide: sideBySide, look: look, anchor: anchor)
    }
}
