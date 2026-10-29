import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

/// The pane kinds Oriel draws itself over a herdr pane that runs a placeholder, named by the pane's label
/// (future-work/plugins/labels): the browser and the default plugins.
enum PluginKind: String, CaseIterable {
    case browser, file, preview, markdown, diff, files

    /// The tab's first part and the placeholder's title.
    var name: String {
        rawValue == "diff" ? "Diff" : rawValue.capitalized
    }

    /// Its SF Symbol: the card's, the tab's and the chooser's icon.
    var symbol: String {
        switch self {
        case .browser: "globe"
        case .file: "doc.text"
        case .preview: "photo"
        case .markdown: "doc.richtext"
        case .diff: "plusminus"
        case .files: "folder"
        }
    }

    /// The kind that opens a file: Markdown; text in the file plugin, also a file with no extension (`Makefile`)
    /// or one the system does not know (`.toml`); anything else (images, PDF, audio, video, archives) in the
    /// preview.
    init(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        if ["md", "markdown", "mdx"].contains(ext) {
            self = .markdown
        } else if ext.isEmpty || type.map({ $0.isDynamic || $0.conforms(to: .text) }) ?? true {
            self = .file
        } else {
            self = .preview
        }
    }
}

extension PaneLabel {
    var kind: PluginKind? {
        PluginKind(rawValue: plugin)
    }

    /// A diff's repo root and source: the last word, `uncommitted` or a commit hash.
    var diff: (root: String, source: String) {
        guard let space = arg.lastIndex(of: " ") else { return (arg, "uncommitted") }
        return (String(arg[..<space]), String(arg[arg.index(after: space)...]))
    }

    /// The card's and the tab's title, from the label alone (menus ask for every tab's): the file's or the root's
    /// name, a diff's `Changes` or short hash.
    var title: String {
        if kind == .diff {
            let source = diff.source
            return source == "uncommitted" ? "Changes" : String(source.prefix(7))
        }
        return (arg as NSString).lastPathComponent
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
/// terminal id as terminals are: what its header and content share.
@MainActor @Observable
final class Plugin {
    let terminalID: String
    var paneID: String
    /// Its arg changes with a rename from elsewhere or the card's own (a diff's source); its iid never does.
    var label: PaneLabel
    @ObservationIgnored weak var store: HostStore?
    /// Unsaved edits: the dot after the title.
    var dirty = false
    var toast: Toast?
    /// The card is to take the keyboard, on the next turn (a first responder set during an update is undone).
    var wantsKeyboard = false

    init(terminalID: String, paneID: String, label: PaneLabel, store: HostStore) {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        self.store = store
    }

    var kind: PluginKind {
        label.kind ?? .file
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
