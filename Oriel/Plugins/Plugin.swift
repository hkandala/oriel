import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

/// The pane kinds Oriel draws itself over a herdr pane that runs a placeholder, named by the pane's label
/// (future-work/plugins/labels): the browser and the default plugins.
enum PluginKind: String, CaseIterable {
    case browser, explorer, git

    /// The tab's first part, the placeholder's title and the chooser's row.
    var name: String {
        self == .explorer ? "File Explorer" : rawValue.capitalized
    }

    static let symbols = Set(allCases.map(\.symbol))

    /// Its SF Symbol: the card's, the tab's and the chooser's icon.
    var symbol: String {
        switch self {
        case .browser: "globe"
        case .explorer: "folder"
        case .git: "arrow.triangle.branch"
        }
    }
}

/// A plugin card's web page (`web/src/<page>.ts`), which its argument picks: the File Explorer's tree, File, Preview
/// or Markdown; Git's diff.
enum PluginPage: String {
    case files, file, preview, markdown, diff

    /// A folder's argument ends in `/`; a file opens by its name alone (a remote file is not read first): Markdown,
    /// then images, PDF, audio and video, then text. A name the system does not know (`.rs`, `Makefile`) is text;
    /// anything else previews, which shows its icon, size and Open With.
    init(_ kind: PluginKind, _ arg: String) {
        guard kind == .explorer else {
            self = .diff
            return
        }
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

    /// File and Markdown: an editor, which takes ⌘S and ⌘F.
    var edits: Bool {
        self == .file || self == .markdown
    }
}

extension PaneLabel {
    /// The words of the five kinds before File Explorer and Git still open.
    var kind: PluginKind? {
        PluginKind(rawValue: ["file": "explorer", "preview": "explorer", "markdown": "explorer", "files": "explorer",
                              "diff": "git"][plugin] ?? plugin)
    }

    /// A diff's repo root and source: the last word when it is `uncommitted` or a commit hash, else Uncommitted.
    var diff: (root: String, source: String) {
        if let space = arg.lastIndex(of: " ") {
            let source = arg[arg.index(after: space)...]
            if source == "uncommitted" || !source.isEmpty && source.allSatisfy(\.isHexDigit) {
                return (String(arg[..<space]), String(source))
            }
        }
        return (arg, "uncommitted")
    }

    /// The card's and the tab's title, from the label alone (menus ask for every tab's): the file's or the root's
    /// name, a diff's `Changes` or short hash.
    var title: String {
        if kind == .git {
            let source = diff.source
            return source == "uncommitted" ? "Changes" : String(source.prefix(7))
        }
        let name = (arg as NSString).lastPathComponent
        return name.isEmpty ? kind?.name ?? plugin : name
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
        return ["sh", "-c", script, "sh", kind?.name ?? plugin, arg]
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

    /// Its arg changes with a rename from elsewhere or the card's own (a diff's source); its iid never does.
    var label: PaneLabel
    /// The content: `web/src/<kind>.ts`.
    let web: WebCard

    init(terminalID: String, paneID: String, label: PaneLabel, place: String?, store: HostStore) {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        // An old Files label names its root without the `/` of a folder.
        let arg = label.plugin == "files" && !label.arg.hasSuffix("/") ? label.arg + "/" : label.arg
        web = WebCard(kind: label.kind ?? .explorer, arg: arg, place: place, store: store)
        name()
    }

    /// The page's identifier names the page it shows: `file.<pane>.page`.
    func name() {
        web.view.setAccessibilityIdentifier("\(web.page.rawValue).\(paneID).page")
    }

    var kind: PluginKind {
        label.kind ?? .explorer
    }

    /// Unsaved edits, as the page reports them: the dot after the title.
    var dirty: Bool {
        web.dirty
    }
}

/// One line at the top of the card with two buttons, the second the default (Reload or Keep Mine, Overwrite or
/// Reload). A button's action ends it.
struct Toast {
    let text: String
    let other: (title: String, action: () -> Void)
    let main: (title: String, action: () -> Void)
}

extension HostStore.Pane {
    /// A browser's or a plugin's label: the pane runs only its placeholder.
    var plugin: PaneLabel? {
        PaneLabel(label).flatMap { $0.kind == nil ? nil : $0 }
    }
}

extension HostStore {
    /// A new plugin pane's label, its iid unique in the session.
    func newLabel(_ kind: PluginKind, arg: String = "") -> PaneLabel {
        let taken = Set(panes.compactMap { PaneLabel($0.label)?.iid })
        return PaneLabel(plugin: kind.rawValue, iid: PaneLabel.newIID(taken: taken), arg: arg)
    }
}
