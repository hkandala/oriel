import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

/// A plugin card's web page (`web/src/<page>.ts`), which its argument picks: Git's home (`<root>`) or a diff
/// (`<root> <source>`); any other plugin's entry (`main`), which draws every place of its card itself through the
/// plugin API (`Bridge`).
enum PluginPage: String, CaseIterable {
    case diff, git, main

    /// Nil for a plugin with no entry (the browser).
    init?(_ plugin: String, _ arg: String) {
        if plugin == "git" {
            // Git's home, or one of its diffs.
            self = PaneLabel(plugin: plugin, iid: "", arg: arg).diff.source == nil ? .git : .diff
        } else if Registry.plugin(plugin)?.entry != nil {
            self = .main
        } else {
            return nil
        }
    }

    /// The card's and the tab's icon while it shows the page.
    var symbol: String {
        switch self {
        case .diff: "plusminus"
        case .git: "arrow.triangle.branch"
        case .main: Registry.missing
        }
    }
}

/// The place a File Explorer card shows, which its page (plugins/explorer/main.ts) picks the same way: its card's and
/// tab's icon, its page's identifier, and whether it takes ⌘S and ⌘F. A folder's argument ends in `/`; a file goes
/// by its name alone (a remote file is not read first): Markdown, then images, PDF, audio and video, then text. A name
/// the system does not know (`.rs`, `Makefile`) is text; anything else previews, which shows its icon, size and Open
/// With.
enum ExplorerPlace: String, CaseIterable {
    case files, file, preview, markdown

    init(_ arg: String) {
        let ext = (arg as NSString).pathExtension.lowercased()
        if arg.hasSuffix("/") {
            self = .files
        } else if ["md", "markdown", "mdx"].contains(ext) {
            self = .markdown
        } else if ext.isEmpty || ["ts", "mts", "cts", "plist"].contains(ext) {
            // `.ts` is TypeScript, not an MPEG-2 stream; a repository's `.plist` is XML.
            self = .file
        } else if let type = UTType(filenameExtension: ext), !type.isDynamic {
            self = [.image, .pdf, .audiovisualContent].contains(where: type.conforms) || !type.conforms(to: .text)
                ? .preview : .file
        } else {
            self = .file
        }
    }

    var symbol: String {
        switch self {
        case .files: "folder"
        case .file: "doc.text"
        case .preview: "photo"
        case .markdown: "doc.richtext"
        }
    }
}

extension PaneLabel {
    /// Its program icon: the place a File Explorer shows, else its plugin's; a missing plugin's.
    var symbol: String {
        manifest.map { $0.id == "explorer" ? ExplorerPlace(place).symbol : $0.icon } ?? Registry.missing
    }

    /// Its plugin; nil when it is not on this Mac (a missing plugin's card shows).
    var manifest: PluginManifest? {
        Registry.plugin(plugin)
    }

    /// The card's and the tab's title, from the label alone (menus ask for every tab's): the file's or the root's
    /// name, a diff's `Changes` or short hash.
    var title: String {
        if manifest?.id == "git", let source = diff.source {
            return source == "uncommitted" ? "Changes" : String(source.prefix(7))
        }
        let name = (arg as NSString).lastPathComponent
        return name.isEmpty ? manifest?.name ?? plugin : name
    }

    /// The pane's command in herdr (ui/browser#in-herdrs-tui): the kind's name, the argument and "Shown in Oriel",
    /// centered and drawn again on a resize. Keys do nothing: `stty raw` makes Ctrl-C and Ctrl-D plain bytes for the
    /// `cat` that swallows them. herdr runs the argv itself, with no shell quoting.
    var placeholder: [String] {
        let script = #"""
        draw() {
          set -- $(stty size 2>/dev/null || echo "24 80"); r=$1 c=$2
          printf '\033[?25l\033[2J'
          line() {
            x=$(( (c - ${#2}) / 2 + 1 )); [ $x -lt 1 ] && x=1
            printf '\033[%d;%dH%b%s\033[0m' "$1" "$x" "$3" "$2"
          }
          y=$(( r / 2 - 2 ))
          line $y "$T" '\033[1m'
          [ -n "$U" ] && line $((y + 2)) "$U" '\033[4;34m'
          line $((y + 4)) "Shown in Oriel" '\033[2m'
        }
        T=$1 U=$2
        stty raw -echo 2>/dev/null
        trap draw WINCH
        draw
        cat <&0 >/dev/null &
        while kill -0 $! 2>/dev/null; do wait $!; done
        """#
        return ["sh", "-c", script, "sh", manifest?.name ?? plugin, arg]
    }
}

/// A plugin pane's card (not the browser's, which has its own), made on first use from its label and kept by
/// terminal id as terminals are: what its header and content share, and its page.
@MainActor @Observable
final class Plugin {
    let terminalID: String
    var paneID: String {
        didSet { name() }
    }

    /// The pane's label as the last snapshot has it: the card's own renames come later. Its iid never changes.
    private(set) var label: PaneLabel
    let manifest: PluginManifest
    /// The content: `web/src/<page>.ts`.
    let web: WebCard
    let header: Header

    init(terminalID: String, paneID: String, label: PaneLabel, manifest: PluginManifest, page: PluginPage,
         place: String?, store: HostStore)
    {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        self.manifest = manifest
        web = WebCard(plugin: manifest.id, page: page, arg: label.place, place: place, store: store)
        header = Header(manifest: manifest)
        name()
        if page == .main {
            web.bridge = Bridge(plugin: self)
        }
        web.view.step = { [weak self] back in
            guard let self, back ? canGoBack : canGoForward else { return false }
            if back {
                goBack()
            } else {
                goForward()
            }
            return true
        }
    }

    /// The page's identifier names the page it shows, a File Explorer's its place: `file.<pane>.page`.
    func name() {
        let page = manifest.id == "explorer" ? ExplorerPlace(web.arg).rawValue : web.page.rawValue
        web.view.setAccessibilityIdentifier("\(page).\(paneID).page")
    }

    /// A plugin's page takes what its manifest `handles` (`save`, `find`); a File Explorer only in File and Markdown.
    func handles(_ command: String) -> Bool {
        let place = manifest.id == "explorer" ? ExplorerPlace(web.arg) : nil
        return web.page == .main && manifest.handles.contains(command) && place != .files && place != .preview
    }

    /// A menu command for the card's page: `save`, `find`, `findNext` or `findPrevious`.
    func command(_ name: String) {
        web.bridge?.event(name, NSNull())
    }

    /// Unsaved edits, as the page reports them: the dot after the title.
    var dirty: Bool {
        web.dirty
    }

    /// The places shown before and after this one, as a browser's history: an argument and its landing each.
    private(set) var back: [(arg: String, at: String?)] = []
    private(set) var forward: [(arg: String, at: String?)] = []
    /// The arguments the card renamed its label to while its renames are under way: a snapshot read before one is no
    /// rename from elsewhere. Cleared once the last one returned (a write waits for the snapshot after it).
    @ObservationIgnored private var renamed: Set<String> = []
    @ObservationIgnored private var renaming = 0

    var canGoBack: Bool {
        !back.isEmpty
    }

    var canGoForward: Bool {
        !forward.isEmpty
    }

    /// Shows another place in the card, after the one it shows; the same place with a landing goes there. The tree
    /// comes back with the file it opened revealed.
    func go(_ arg: String, at place: String? = nil) {
        guard arg != web.arg else {
            if web.page == .main {
                web.bridge?.place(arg, at: place)
            } else if let place {
                web.send(["op": "reveal", "at": place])
            }
            return
        }
        // A path that makes no label (a control character, over 1024 characters) opens nothing, as a linked open.
        guard PaneLabel(PaneLabel(plugin: manifest.id, iid: label.iid, arg: arg).text) != nil else { return }
        leave { plugin in
            plugin.back.append((plugin.web.arg, plugin.landing(arg, place)))
            plugin.forward = []
            plugin.show(arg, at: place)
        }
    }

    /// Where a place comes back when Back returns to it from `arg`: where it came back from, so the tree reveals the
    /// file it opened, the Git home the change (`place`) or the commit (`arg`) it opened.
    private func landing(_ arg: String, _ place: String?) -> String? {
        web.page == .diff ? nil : place ?? arg
    }

    func goBack() {
        leave { plugin in
            guard let last = plugin.back.popLast() else { return }
            plugin.forward.append((plugin.web.arg, nil))
            plugin.show(last.arg, at: last.at)
        }
    }

    func goForward() {
        leave { plugin in
            guard let next = plugin.forward.popLast() else { return }
            plugin.back.append((plugin.web.arg, plugin.landing(next.arg, next.at)))
            plugin.show(next.arg, at: next.at)
        }
    }

    /// Open With's pick of another plugin: the pane's label names it, with the same iid and argument, and the card is
    /// made again as its card.
    func reopen(as other: PluginManifest) {
        leave { plugin in
            let text = PaneLabel(plugin: other.id, iid: plugin.label.iid, arg: plugin.web.arg).text
            guard let store = plugin.web.store else { return }
            Task { [paneID = plugin.paneID] in await store.write { try await $0.rename(pane: paneID, label: text) } }
        }
    }

    /// Unsaved edits ask first: Back or a click would drop them. The toast keeps the card weakly.
    private func leave(_ then: @escaping (Plugin) -> Void) {
        guard web.dirty else { return then(self) }
        web.bridge?.dropToast()
        let name = (web.arg as NSString).lastPathComponent
        web.toast = Toast(text: "\(name) has unsaved edits.", other: ("Discard", { [weak self] in self.map(then) }),
                          main: ("Keep Editing", {}))
    }

    /// The label follows the place, so a reload or a card made again comes back to it.
    private func show(_ arg: String, at place: String?) {
        web.show(arg, at: place)
        name()
        let text = PaneLabel(plugin: manifest.id, iid: label.iid, arg: arg).text, paneID = paneID
        guard let store = web.store else { return }
        renamed.insert(arg)
        renaming += 1
        // Not `HostStore.rename`, which skips a label the last snapshot has: a quick Back renames to it again.
        Task {
            await store.write { try await $0.rename(pane: paneID, label: text) }
            renaming -= 1
            if renaming == 0 {
                renamed = []
            }
        }
    }

    /// A snapshot's new label: the card's own rename, or a new place from elsewhere (an agent's `herdr pane rename`),
    /// shown after the one the card shows, as a browser's.
    /// ponytail: a place from elsewhere drops unsaved edits without asking, as a rename always did.
    func follow(_ label: PaneLabel) {
        self.label = label
        let arg = label.place
        if arg != web.arg, !renamed.contains(arg) {
            back.append((web.arg, nil))
            forward = []
            web.show(arg, at: nil)
            name()
        }
    }
}

/// Back and Forward at the left of row 2.
struct BackForward: View {
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        // No opacity of their own: ChromeStyle dims a disabled button.
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", help: "Back", key: .init("["), size: 22) { plugin.goBack() }
                .disabled(!plugin.canGoBack)
                .accessibilityIdentifier("pane.\(plugin.paneID).go-back")
            IconButton(symbol: "chevron.right", help: "Forward", key: .init("]"), size: 22) { plugin.goForward() }
                .disabled(!plugin.canGoForward)
                .accessibilityIdentifier("pane.\(plugin.paneID).go-forward")
        }
        .foregroundStyle(look.paneButton)
    }
}

/// One line at the top of the card with two buttons, the second the default (Reload or Keep Mine, Overwrite or
/// Reload). A button's action ends it.
struct Toast {
    let text: String
    /// None: the main button alone.
    let other: (title: String, action: () -> Void)?
    let main: (title: String, action: () -> Void)
}

extension HostStore.Pane {
    /// A browser's or a plugin's label, also of a plugin not on this Mac: the pane runs only its placeholder.
    var plugin: PaneLabel? {
        PaneLabel(label)
    }
}

extension HostStore {
    /// A new plugin pane's label, its iid unique in the session.
    func newLabel(_ plugin: PluginManifest, arg: String = "") -> PaneLabel {
        let taken = Set(panes.compactMap { PaneLabel($0.label)?.iid })
        return PaneLabel(plugin: plugin.id, iid: PaneLabel.newIID(taken: taken), arg: arg)
    }
}
