import HerdrKit
import WebKit

/// What a browser card takes from its machine: its pane's command in herdr, its addresses and its data store.
extension Browser {
    /// The pane's command in herdr (future-work/web-page#in-herdrs-tui): "Browser", the address it started with, and
    /// "Shown in Oriel", centered and drawn again on a resize. Keys do nothing: `stty raw` makes Ctrl-C and Ctrl-D
    /// plain bytes for the `cat` that swallows them. herdr runs the argv itself, with no shell quoting.
    static func placeholder(_ label: PaneLabel) -> [String] {
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
        return ["sh", "-c", script, "sh", "Browser", label.arg]
    }

    /// The machine's own loopback on any port, This Mac's files, and a few developer sites.
    static let safe = ["github.com", "gitlab.com", "bitbucket.org", "developer.apple.com",
                       "developer.mozilla.org", "docs.github.com", "vercel.com"]

    static func origin(_ url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host ?? "")" + (url.port.map { ":\($0)" } ?? "")
    }

    /// `http`, `https`, and `file` on This Mac only; at most 1024 characters (the label's argument).
    static func url(_ text: String, local: Bool) -> URL? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 1024 else { return nil }
        let full = text.contains("://") ? text : "http://\(text)"
        guard let url = URL(string: full), url.absoluteString.count <= 1024, let scheme = url.scheme?.lowercased()
        else { return nil }
        return ["http", "https"].contains(scheme) && url.host != nil || scheme == "file" && local ? url : nil
    }

    /// One store per machine (future-work/web-page#profiles): cookies, storage and the cache stay apart.
    private static var stores: [String: WKWebsiteDataStore] = [:]

    static func dataStore(_ machine: Machine) -> WKWebsiteDataStore {
        if let store = stores[machine.id] {
            return store
        }
        // This Mac's fixed id; a remote machine's from its id, else kept in memory only.
        let id = UUID(uuidString: machine.isRemote ? machine.id : "6F726965-6C00-4000-8000-746869734D61")
        let store = id.map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        stores[machine.id] = store
        return store
    }
}
