import Foundation

/// One request of the `ovvi` command (agent-control/protocol): `‹id›.req` in the machine's mailbox
/// `~/.cache/ovvi/rpc`, NUL-separated fields: `ovvi-req`, the protocol version, the command's working folder, then
/// the arguments as typed.
public struct AgentRequest: Equatable, Sendable {
    /// The protocol this kit speaks: in each request, in `ovvi-open` and on the script's second line.
    public static let version = 1
    /// The most a request (64 KiB) and a copy's standard input (1 MiB) may hold.
    public static let limit = 64 << 10, inputLimit = 1 << 20

    public let cwd: String
    public let argv: [String]

    public enum Problem: Error, Equatable {
        /// Over 64 KiB or 64 fields.
        case tooLarge
        /// Not a request: no marker, no version, no folder.
        case unreadable
        /// A newer protocol than this kit's.
        case newer(Int)
    }

    /// The fields of `‹id›.req` as `take` read it: at most one byte over the limit, so a larger one shows.
    public init(_ data: Data) throws(Problem) {
        guard data.count <= Self.limit else { throw .tooLarge }
        var fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self)
        }
        // Each field ends with a NUL, so the last split is empty.
        guard fields.popLast() == "" else { throw .unreadable }
        guard fields.count <= 64 else { throw .tooLarge }
        guard fields.count >= 3, fields[0] == "ovvi-req", let version = Int(fields[1]) else { throw .unreadable }
        guard version <= Self.version else { throw .newer(version) }
        cwd = fields[2]
        argv = Array(fields[3...])
    }

    /// A lowercase UUID version 4, as the command makes: every mailbox path is built from it, so a token can never
    /// name another file.
    public static func isID(_ id: String) -> Bool {
        id.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil
    }
}

/// The mailbox runs, each one run on the request's machine.
public extension Exec {
    /// When a session opens on the machine: makes the folders, removes mailbox files older than 60 minutes and reads
    /// the script's version; a second run writes `script` when the machine's is missing or older, never over a newer
    /// one (agent-control/remote). The version is the second line's `# ovvi-cli ‹protocol›.‹revision›`: a fixed
    /// script gets a new revision and replaces the old one without a new protocol.
    func prepareAgent(script: Data) async {
        let line = try? await output(["sh", "-c", #"""
        d=$HOME/.cache/ovvi; mkdir -p "$d/bin" "$d/rpc" && chmod 700 "$d/rpc" &&
        find "$d/rpc" -type f -mmin +60 -exec rm -f {} + ; sed -n 2p "$d/bin/ovvi" 2>/dev/null
        """#])
        let ours = String(decoding: script, as: UTF8.self).split(separator: "\n").dropFirst().first.map(String.init)
        guard let line, scriptVersion(line).lexicographicallyPrecedes(scriptVersion(ours ?? "")) else { return }
        await succeeds(#"""
        f=$HOME/.cache/ovvi/bin/ovvi; base64 -d >"$f.$$" && chmod 755 "$f.$$" && mv "$f.$$" "$f" || rm -f "$f.$$"
        """#, [], input: base64Lines(script))
    }

    /// Takes the request: renames `‹id›.req` to `‹id›.run` and reads it, at most one byte over the limit. Nil when
    /// another Ovvi took it first, or the command gave up.
    func take(request id: String) async throws -> Data? {
        guard AgentRequest.isID(id) else { return nil }
        let text = try await output(["sh", "-c", #"""
        cd "$HOME/.cache/ovvi/rpc" && mv -- "$1.req" "$1.run" && head -c "$2" "$1.run" | base64
        """#, "sh", id, "\(AgentRequest.limit + 1)"])
        return text.isEmpty ? nil : Data(base64Encoded: text, options: .ignoreUnknownCharacters)
    }

    /// A copy's standard input, `‹id›.in`, at most one byte over its limit; empty when there is none.
    func input(request id: String) async throws -> Data {
        guard AgentRequest.isID(id) else { return Data() }
        let text = try await output(
            ["sh", "-c", #"f=$HOME/.cache/ovvi/rpc/$1.in; [ ! -f "$f" ] || head -c "$2" "$f" | base64"#,
             "sh", id, "\(AgentRequest.inputLimit + 1)"],
            timeout: .seconds(30),
        )
        return Data(base64Encoded: text, options: .ignoreUnknownCharacters) ?? Data()
    }

    /// Writes `‹id›.out`, then `‹id›.exit` (the code on its first line, then `err`), each to a temporary name and
    /// then renamed, so the command never reads half a file; removes `‹id›.run` and `‹id›.in`.
    func answer(request id: String, code: Int32, out: Data, err: String) async throws {
        guard AgentRequest.isID(id) else { return }
        _ = try await checkedOutput(["sh", "-c", #"""
        cd "$HOME/.cache/ovvi/rpc" && base64 -d >"$1.o" && mv "$1.o" "$1.out" &&
        printf '%s\n%s' "$2" "$3" >"$1.e" && mv "$1.e" "$1.exit"; s=$?; rm -f "$1.run" "$1.in"; exit $s
        """#, "sh", id, "\(code)", err], input: base64Lines(out), timeout: .seconds(30))
    }
}

/// `# ovvi-cli 1.1` as [1, 1]; none for another line.
private func scriptVersion(_ line: String) -> [Int] {
    guard line.hasPrefix("# ovvi-cli ") else { return [] }
    return line.dropFirst(12).split(separator: ".").map { Int($0) ?? 0 }
}
