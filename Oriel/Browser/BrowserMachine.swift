import HerdrKit
import Network
import WebKit

/// What a browser card takes from its machine: its pane's command in herdr, its addresses and its data store.
extension Browser {
    /// The pane's command in herdr (ui/browser#in-herdrs-tui): "Browser", the address it started with, and
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

    static let loopback = ["localhost", "127.0.0.1", "::1"]

    /// Developer sites that load by themselves (with the machine's loopback and This Mac's files, `approved`).
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

    /// One store per machine (ui/browser#profiles): cookies, storage and the cache stay apart.
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

    /// Removing a machine removes its store and its approvals; a store a window still uses stays.
    static func forget(_ machine: Machine) {
        stores[machine.id] = nil
        UserDefaults.standard.removeObject(forKey: "browserApprovals.\(machine.id)")
        if let id = UUID(uuidString: machine.id) {
            Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
    }

    // MARK: Origins

    func approved(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.isFileURL && store?.machine.isRemote == false }
        return Self.loopback.contains(host) || host.hasSuffix(".localhost") || Self.safe.contains(host)
            || host.hasSuffix(".vercel.app") || host.hasSuffix(".netlify.app") || approvals.contains(Self.origin(url))
    }

    /// Web origins only, the newest 200.
    func approve(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased()), !approved(url) else { return }
        UserDefaults.standard.set(Array((approvals + [Self.origin(url)]).suffix(200)), forKey: approvalsKey)
    }

    /// Per device, per machine.
    private var approvalsKey: String {
        "browserApprovals.\(store?.machine.id ?? "")"
    }

    private var approvals: [String] {
        UserDefaults.standard.stringArray(forKey: approvalsKey) ?? []
    }

    // MARK: Remote localhost

    /// The `<machine>` of `<machine>.localhost` (ui/browser#remote-localhost): the name in lowercase
    /// letters, digits and dashes.
    static func alias(_ name: String) -> String {
        let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.isEmpty ? "machine" : words.joined(separator: "-")
    }

    /// WebKit never proxies a loopback name, so a remote machine's `localhost` loads as `<machine>.localhost`, which
    /// its proxy asks the machine for as `localhost`. nil alias: This Mac.
    static func web(_ url: URL, _ alias: String?) -> URL {
        guard let alias, loopback.contains(url.host?.lowercased() ?? ""),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "\(alias).localhost"
        return parts.url ?? url
    }

    /// The machine's view of a page's address: `localhost` again, for any `<name>.localhost` (the proxy asks the
    /// machine for `localhost`), also the one of a name the machine had before a rename.
    static func shown(_ url: URL, _ alias: String?) -> URL {
        guard alias != nil, url.host?.lowercased().hasSuffix(".localhost") == true,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "localhost"
        return parts.url ?? url
    }

    /// The machine's proxy in its store, before the card's first load; nil when it did not start. The card gives it
    /// back when it goes (`SSHExec.closeProxy`).
    /// The card's content rule goes in with it: a page's images, fetches, frames and popups to a loopback name
    /// would reach This Mac, as WebKit never proxies one.
    static func proxy(_ machine: Machine, _ store: WKWebsiteDataStore,
                      _ content: WKUserContentController) async -> SSHExec?
    {
        guard let ssh = await machine.exec() as? SSHExec, let port = try? await ssh.openProxy() else { return nil }
        guard let rule = await noLoopback.value else {
            await ssh.closeProxy()
            return nil
        }
        content.add(rule)
        store.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))]
        return ssh
    }

    /// Every spelling of loopback WebKit loads without a proxy (`127.1`, `localhost.`, `[::ffff:7f00:1]`, checked);
    /// `<name>.localhost` goes on to the proxy. Content rules have no alternation: one rule each.
    private static let noLoopback = Task { @MainActor in
        // Regexes in JSON strings: each backslash twice.
        // A user name before the host (`u@localhost`) too.
        let rules = [#"localhost[.]?[:/]"#, #"127\\."#, #"\\[::1\\]"#, #"\\[::ffff:7f"#]
            .map { #"^[^:]+://([^/]*@)?"# + $0 }
            .map { #"{"trigger":{"url-filter":"\#($0)"},"action":{"type":"block"}}"# }
        return try? await WKContentRuleListStore.default()
            .compileContentRuleList(
                forIdentifier: "oriel-no-loopback",
                encodedContentRuleList: "[\(rules.joined(separator: ","))]",
            )
    }

    /// A failed load in the app's words, and the line under it. The proxy refuses a port that does not answer and a
    /// name the machine cannot reach; WebKit reports either code for it (checked).
    func failureText(_ error: NSError, _ url: URL?) -> (text: String, hint: String?) {
        let place = url.map { [$0.host, $0.port.map(String.init)].compactMap(\.self).joined(separator: ":") } ?? ""
        let local = url?.host.map { Self.loopback.contains($0) } ?? false
        let machine = alias == nil ? nil : store?.machine.name
        let refused = error.code == NSURLErrorCannotConnectToHost || machine != nil && error.code == NSURLErrorBadURL
        return if refused, let machine, store?.state != .live {
            ("\(machine) is not connected", nil)
        } else if refused, local {
            ("Nothing answers on \(place)" + (machine.map { " on \($0)" } ?? ""), "Is the dev server running?")
        } else if refused, let machine {
            ("\(machine) cannot reach \(place)", nil)
        } else if error.code == NSURLErrorCannotFindHost {
            ("Cannot find \(place)", nil)
        } else {
            (error.localizedDescription, nil)
        }
    }
}
