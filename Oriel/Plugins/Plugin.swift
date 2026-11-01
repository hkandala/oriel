import HerdrKit
import SwiftUI

/// The place a File Explorer card shows: its card's and tab's icon, its page's identifier, and whether it takes ⌘S
/// and ⌘F. By the rule and the extensions its page picks it by (`kind` in plugins/explorer/place.ts, places.json): a
/// folder's tree; Markdown; text (no extension too); Preview for the kinds it draws and the known kinds that are not
/// text; else File.
enum ExplorerPlace: String, CaseIterable {
    case files, file, preview, markdown

    init(_ arg: String) {
        let ext = (arg as NSString).pathExtension.lowercased(), places = Registry.places
        if arg.hasSuffix("/") {
            self = .files
        } else if places["markdown", default: []].contains(ext) {
            self = .markdown
        } else if ext.isEmpty || places["text", default: []].contains(ext) {
            self = .file
        } else {
            self = ["image", "pdf", "audio", "video", "binary"].contains { places[$0, default: []].contains(ext) }
                ? .preview : .file
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
    /// name, a diff's `Working Tree` or short hash. A page's `document.title` comes first (`Page.pluginTitle`).
    var title: String {
        if manifest?.id == "git", let source = diffSource {
            return source == "uncommitted" ? "Working Tree" : String(source.prefix(7))
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

extension Page {
    /// A plugin card's title: its page's `document.title` once its card is made, else the label's.
    func pluginTitle(_ pane: HostStore.Pane, _ label: PaneLabel) -> String {
        let title = pane.terminalID.flatMap(terminals.builtPlugin)?.web.title ?? ""
        return title.isEmpty ? label.title : title
    }

    /// What VoiceOver reads for a card: a plugin card's title (Git's commit subject), as its header shows it.
    func cardLabel(_ pane: HostStore.Pane?) -> String {
        pane.map { pane in
            pane.plugin.flatMap { pane.browser == nil ? pluginTitle(pane, $0) : nil } ?? pane.cardTitle
        } ?? "terminal"
    }
}

extension Image {
    /// An SF Symbol, or the app's own symbol of that name (`Assets.xcassets`), for what a manifest names: a plugin's
    /// icon, a control's or a menu item's symbol.
    init(symbol name: String) {
        self = NSImage.own.contains(name) ? Image(name) : Image(systemName: name)
    }
}

extension NSImage {
    /// The app's own symbols: Git's `source.branch` (Material Design Icons' `source-branch`).
    static let own: Set = ["source.branch"]

    static func symbol(_ name: String) -> NSImage? {
        own.contains(name) ? NSImage(named: name) : NSImage(systemSymbolName: name, accessibilityDescription: nil)
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
    /// The content: the plugin's entry page.
    let web: WebCard
    let header: Header

    init(terminalID: String, paneID: String, label: PaneLabel, manifest: PluginManifest, place: String?,
         store: HostStore)
    {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        self.manifest = manifest
        web = WebCard(plugin: manifest.id, arg: label.place, place: place, store: store)
        header = Header(manifest: manifest)
        name()
        web.bridge = Bridge(plugin: self)
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

    /// The page's identifier names its plugin, a File Explorer's its place: `git.<pane>.page`, `file.<pane>.page`.
    func name() {
        let page = manifest.id == "explorer" ? ExplorerPlace(web.arg).rawValue : manifest.id
        web.view.setAccessibilityIdentifier("\(page).\(paneID).page")
    }

    /// A plugin's page takes what its manifest `handles` (`save`, `find`); a File Explorer saves in File and Markdown,
    /// and finds there and in the tree (its filter).
    func handles(_ command: String) -> Bool {
        let place = manifest.id == "explorer" ? ExplorerPlace(web.arg) : nil
        return manifest.handles.contains(command) && place != .preview && (place != .files || command == "find")
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
            web.bridge?.place(arg, at: place)
            return
        }
        // A path that makes no label (a control character, over 1024 characters) opens nothing, as a linked open.
        guard PaneLabel(PaneLabel(plugin: manifest.id, iid: label.iid, arg: arg).text) != nil else { return }
        leave { plugin in
            // Back lands where it came back from: the tree reveals the file it opened, Git's home the change.
            plugin.back.append((plugin.web.arg, place ?? arg))
            plugin.forward = []
            plugin.show(arg, at: place)
        }
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
            plugin.back.append((plugin.web.arg, next.at ?? next.arg))
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

    /// Unsaved edits ask first: Back, a click or a reload would drop them. The toast keeps the card weakly.
    func leave(_ then: @escaping (Plugin) -> Void) {
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

/// One line at the top of the card with two buttons, the second the default. A button's action ends it.
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
    /// A browser or plugin pane with only its shell in front gets its placeholder again, typed into that shell once
    /// per shell process (plugins/labels#the-placeholder): herdr starts a fresh shell under the label after a restart,
    /// and a pane labeled outside the app may have none. Never into a pane that runs another program.
    func keepPlaceholder(_ pane: Pane) {
        guard let label = pane.plugin, let program = pane.program, let client else { return }
        guard program.isShell else {
            // A slow shell startup after a restart can outlast the first look: one more, later.
            if !program.isPlaceholder, pane.rechecked != pane.terminalID {
                pane.rechecked = pane.terminalID
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    await askProgram(pane.id)
                }
            }
            return
        }
        guard let shell = program.foreground.first?.pid, pane.placed != shell else { return }
        pane.placed = shell
        // In place of the shell, so the pane runs only the placeholder; base64, which any login shell passes on. The
        // space keeps it out of a history that ignores such lines (fish; zsh and bash when set to).
        let line = " exec " + SSHExec.envelope(["exec"] + label.placeholder)
        Task { try? await client.sendInput(line, keys: ["enter"], pane: pane.id) }
    }

    /// A new plugin pane's label, its iid unique in the session.
    func newLabel(_ plugin: PluginManifest, arg: String = "") -> PaneLabel {
        let taken = Set(panes.compactMap { PaneLabel($0.label)?.iid })
        return PaneLabel(plugin: plugin.id, iid: PaneLabel.newIID(taken: taken), arg: arg)
    }
}
