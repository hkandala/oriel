import AppKit
import HerdrKit
import SwiftUI

/// A Files card's tree and git data, kept on its `Plugin`: the outline view is made once, as a browser's web view
/// is, so a float or a move keeps the open folders and the scroll. Folders are listed when they open, and again with
/// the root on each change the watch sees.
@MainActor @Observable
final class FileTree: NSObject {
    /// A row, by its path from the root.
    final class Node {
        let path: String
        var isFolder: Bool
        var letter: Character?
        var ignored: Bool

        init(path: String, isFolder: Bool, letter: Character?, ignored: Bool) {
            self.path = path
            self.isFolder = isFolder
            self.letter = letter
            self.ignored = ignored
        }

        var name: String {
            (path as NSString).lastPathComponent
        }

        /// As `Files.list` sorts: folders first, then by name as the Finder does.
        static func before(_ lhs: Node, _ rhs: Node) -> Bool {
            lhs.isFolder != rhs.isFolder ? lhs.isFolder : lhs.name
                .localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// The filter field's text: the tree shows the matching files with their folders.
    var filter = "" {
        // Not on an equal write: the field writes its text again as it loses the keyboard.
        didSet {
            if filter != oldValue {
                refilter()
            }
        }
    }

    /// Why the root could not be listed.
    private(set) var failure: String?
    /// The root when it is a git repository's root and git can run.
    private(set) var repo: String?
    /// The filter matches no file.
    private(set) var noMatches = false
    private(set) var changes: [Git.Change] = []
    private(set) var history: [(commit: Git.Commit, row: Git.GraphRow)] = []
    private(set) var branch = ""
    /// The history is read only while the section is open.
    var showsGit = false {
        didSet {
            if showsGit {
                Task { await loadGit() }
            }
        }
    }

    @ObservationIgnored let outline = Outline()
    @ObservationIgnored let scroll = NSScrollView()
    @ObservationIgnored var look = Look(style: .glass, dark: true) {
        didSet { outline.reloadData() }
    }

    @ObservationIgnored private weak var plugin: Plugin?
    @ObservationIgnored private weak var page: Page?
    @ObservationIgnored private var root = ""
    @ObservationIgnored private var exec: (any Exec)?
    /// Each listed folder's rows, by its path ("" the root); the nodes by path, so the outline keeps their state.
    @ObservationIgnored private var listings: [String: [Node]] = [:]
    @ObservationIgnored private var nodes: [String: Node] = [:]
    @ObservationIgnored private var expanded: Set<String> = []
    /// Every file under the root, read when a filter starts after a change; its rows while one is typed.
    @ObservationIgnored private var paths: [String]?
    @ObservationIgnored private var matches: [String: [Node]]?
    @ObservationIgnored private var loadingPaths = false

    init(plugin: Plugin) {
        self.plugin = plugin
        super.init()
        outline.headerView = nil
        let column = NSTableColumn()
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.style = .inset
        outline.backgroundColor = .clear
        outline.rowHeight = 24
        outline.indentationPerLevel = 14
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.onDoubleClick = { [weak self] row in self?.doubleClicked(row) }
        outline.onKeyboard = { [weak self] in
            guard let self, let plugin = self.plugin else { return }
            page?.terminals.claimed(plugin.terminalID)
        }
        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
    }

    /// While the card shows: lists the root, then again on each change. Another root starts over.
    func run(_ root: String, page: Page) async {
        self.page = page
        outline.setAccessibilityIdentifier("files.\(plugin?.paneID ?? "").tree")
        if root != self.root {
            self.root = root
            (listings, nodes, expanded, paths, matches) = ([:], [:], [], nil, nil)
            (failure, repo, branch, changes, history) = (nil, nil, "", [], [])
            outline.reloadData()
        }
        let exec = await page.store.machine.exec()
        self.exec = exec
        let repo = await gitUsable.value ? await Git.root(root, exec: exec) : nil
        guard root == self.root else { return }
        self.repo = repo == root ? root : nil
        await relist()
        for await _ in Files.watch(root, exec: exec) {
            await relist()
        }
    }

    func collapseAll() {
        outline.collapseItem(nil, collapseChildren: true)
        expanded = []
        listings = listings.filter(\.key.isEmpty)
    }

    func open(_ path: String) {
        let path = (root as NSString).appendingPathComponent(path)
        Task { await page?.open(.opening(path), arg: path) }
    }

    /// The diff of the uncommitted changes at this file, or of this commit.
    func openDiff(_ source: String, at file: String? = nil) {
        guard let repo else { return }
        Task { await page?.open(.diff, arg: "\(repo) \(source)", at: file) }
    }

    private func relist() async {
        // Read again when the next filter starts.
        if filter.isEmpty {
            paths = nil
        }
        for folder in [""] + expanded.sorted() {
            await list(folder)
        }
        await loadGit()
    }

    private func list(_ folder: String) async {
        guard let exec else { return }
        let root = root
        do {
            let entries = try await Files.list((root as NSString).appendingPathComponent(folder), repo: repo,
                                               exec: exec)
            guard root == self.root else { return }
            listings[folder] = entries.map { entry in
                let path = (folder as NSString).appendingPathComponent(entry.name)
                guard let node = nodes[path] else {
                    let node = Node(path: path, isFolder: entry.isFolder, letter: entry.letter, ignored: entry.ignored)
                    nodes[path] = node
                    return node
                }
                (node.isFolder, node.letter, node.ignored) = (entry.isFolder, entry.letter, entry.ignored)
                return node
            }
            if folder.isEmpty, failure != nil {
                failure = nil
            }
            if matches == nil {
                outline.reloadItem(nodes[folder], reloadChildren: true)
            }
        } catch {
            guard root == self.root else { return }
            if folder.isEmpty {
                failure = "Can't list \(root)"
                (listings, expanded) = ([:], [])
                outline.reloadData()
            } else {
                expanded.remove(folder)
            }
        }
    }

    private func loadGit() async {
        guard let repo, let exec else { return }
        // ponytail: with the root's listing, three `git status` runs per change on disk; one porcelain=v2 run for
        // the branch and the changes when a big repository makes that slow.
        async let status = Git.status(repo, exec: exec)
        async let head = GitStatus.of(repo, exec: exec)
        let commits = await showsGit ? (try? Git.log(repo, exec: exec)) : nil
        let (changes, branch) = await ((try? status) ?? [], head?.branch ?? "")
        // Only a change: Observation redraws on every write, and a build changes files every second.
        guard repo == self.repo else { return }
        if branch != self.branch {
            self.branch = branch
        }
        if changes != self.changes {
            self.changes = changes
        }
        if let commits, commits.map(\.hash) != history.map(\.commit.hash) {
            history = Array(zip(commits, Git.graph(commits)))
        }
    }

    private func refilter() {
        guard !filter.isEmpty else {
            matches = nil
            noMatches = false
            outline.reloadData()
            for path in expanded.sorted(by: { $0.count < $1.count }) {
                outline.expandItem(nodes[path])
            }
            return
        }
        guard let paths else { return loadPaths() }
        let letters = Dictionary(changes.map { ($0.path, $0.letter) }, uniquingKeysWith: { first, _ in first })
        var rows: [String: [Node]] = [:], seen: Set<String> = []
        // ponytail: the first 5,000 matches, all open at once; a lazy outline when a one-letter filter needs more.
        let found = paths.lazy
            .filter { ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(self.filter) }
        for path in found.prefix(5000) {
            var path = path, isFolder = false
            // The file, then each of its folders once.
            while seen.insert(path).inserted {
                let folder = (path as NSString).deletingLastPathComponent
                rows[folder, default: []].append(Node(path: path, isFolder: isFolder,
                                                      letter: isFolder ? nil : letters[path], ignored: false))
                guard !folder.isEmpty else { break }
                (path, isFolder) = (folder, true)
            }
        }
        matches = rows.mapValues { $0.sorted(by: Node.before) }
        noMatches = rows.isEmpty
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
    }

    private func loadPaths() {
        guard !loadingPaths, let exec else { return }
        loadingPaths = true
        let root = root
        Task {
            let paths = await Result { try await Files.paths(root, repo: repo, exec: exec) }
            loadingPaths = false
            // Another root starts its own read.
            if root == self.root {
                switch paths {
                case let .success(paths): self.paths = paths
                case .failure: failure = "Can't read the files in \(root)"
                }
            }
            if self.paths != nil || root != self.root {
                refilter()
            }
        }
    }

    private func children(_ item: Any?) -> [Node] {
        (matches ?? listings)[(item as? Node)?.path ?? ""] ?? []
    }

    @objc private func clicked() {
        guard NSApp.currentEvent?.modifierFlags.contains(.command) == true,
              let node = outline.item(atRow: outline.clickedRow) as? Node, !node.isFolder else { return }
        open(node.path)
    }

    private func doubleClicked(_ row: Int) {
        guard let node = outline.item(atRow: row) as? Node else { return }
        if !node.isFolder {
            open(node.path)
        } else if outline.isItemExpanded(node) {
            outline.collapseItem(node)
        } else if outlineView(outline, shouldExpandItem: node) {
            outline.expandItem(node)
        }
    }
}

extension FileTree: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(item).count
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(item)[index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isFolder == true
    }

    func outlineView(_ outline: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let row = outline.makeView(withIdentifier: FileRow.id, owner: nil) as? FileRow ?? FileRow()
        row.show(node, look: look, id: "files.\(plugin?.paneID ?? "").item.\(node.path)")
        return row
    }

    /// A folder lists before it opens: rows reloaded while the outline slid them open stayed half drawn (on CI).
    func outlineView(_: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard matches == nil, let node = item as? Node, listings[node.path] == nil else { return true }
        Task {
            await list(node.path)
            if listings[node.path] != nil {
                outline.expandItem(node)
            }
        }
        return false
    }

    /// Only the tree's own folders: the filter's open all theirs.
    func outlineViewItemWillExpand(_ notification: Notification) {
        guard matches == nil, let node = notification.userInfo?["NSObject"] as? Node else { return }
        expanded.insert(node.path)
    }

    /// A closed folder lists again when it opens.
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard matches == nil, let node = notification.userInfo?["NSObject"] as? Node else { return }
        let inside = { (path: String) in path == node.path || path.hasPrefix(node.path + "/") }
        expanded = expanded.filter { !inside($0) }
        listings = listings.filter { !inside($0.key) }
    }
}
