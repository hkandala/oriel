import CryptoKit
import Foundation
import HerdrKit

/// pi (resources/research/agents/pi.md). Started with `-e <pi-oriel> --oriel ~/.cache/oriel/chat/T/pi.jsonl`:
/// pi-oriel (`pi-oriel.ts` in the app, written to the pane's machine before the launch) appends a line to that state
/// file when the session changes (with its transcript), on `/tree`, when an extension dialog opens or closes, when pi
/// starts or stops working, and when the session ends. The transcript is the history; the state file is the phase.
struct PiAgent: ChatAdapter {
    static let command = "pi"
    let token: String
    static let stopKeys = ["escape"]
    static let quit = "/quit"
    /// Kept with the chat, which keeps its adapter: what a follow that starts again goes on from.
    private let kept = Kept()

    @MainActor private final class Kept {
        var transcript = PiTranscript()
        var phase = Chat.Phase.starting
        /// The phase a dialog interrupted, back when it closes.
        var beforeDialog = Chat.Phase.ready

        nonisolated init() {}
    }

    /// The extension, and its file on the machine, named by its content: two versions of Oriel never fight over one.
    private static let source = Bundle.main.url(forResource: "pi-oriel", withExtension: "ts")
        .flatMap { try? Data(contentsOf: $0) }
    private static let file = source.map { source in
        ".cache/oriel/pi-oriel-" + SHA256.hash(data: source).prefix(4).map { String(format: "%02x", $0) }.joined()
            + ".ts"
    }

    /// Under the home folder of the pane's machine, beside Claude Code's side files (the same 30-day sweep); pi-oriel
    /// makes its folder.
    private static func state(_ token: String) -> String {
        ".cache/oriel/chat/\(token)/pi.jsonl"
    }

    static func flags(_ token: String, resume: String?) -> String {
        "-e ~/\(file ?? "") --oriel ~/\(state(token))" + (resume.map { " " + $0 } ?? "")
    }

    /// herdr's pi integration reports the session's file. Single quotes read the same in sh, bash, zsh and fish when
    /// the path holds no quote and no backslash.
    static func resume(_ session: String) -> String? {
        guard session.hasPrefix("/"), !session.contains(where: { "'\\".contains($0) }),
              !session.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return "--session '\(session)'"
    }

    /// One run writes the extension, whole: base64 (the relay passes lines), a temporary file, then a rename. pi exits
    /// at once when `-e` names no file: no chat then. It sweeps old side files (`ChatAdapters.sweep`).
    static func prepare(_ token: String, resume: String?, on exec: any Exec) async -> String? {
        guard let source, let file else { return nil }
        let script = #"""
        umask 077; d=$HOME/.cache/oriel; f=$HOME/$1
        mkdir -p "$d" && chmod 700 "$d" && base64 -d >"$f.$$" && mv "$f.$$" "$f" || exit 1
        \#(ChatAdapters.sweep); exit 0
        """#
        guard let channel = try? await exec.run(["sh", "-c", script, "sh", file]) else { return nil }
        channel.write(source.base64EncodedString())
        channel.closeInput()
        return await channel.exit().status == 0 ? command + " " + flags(token, resume: resume) : nil
    }

    /// `--oriel …/.cache/oriel/chat/T/pi.jsonl` with T a lowercase UUID: the launcher's `pi` and its `pi.real` both
    /// carry it.
    init?(_ foreground: [Program.Foreground]) {
        for process in foreground {
            guard let flag = process.argv.firstIndex(of: "--oriel"), flag + 1 < process.argv.count else { continue }
            let parts = process.argv[flag + 1].split(separator: "/").suffix(5).map(String.init)
            guard parts.count == 5, parts[0 ..< 3] == [".cache", "oriel", "chat"], parts[4] == "pi.jsonl",
                  UUID(uuidString: parts[3]) != nil, parts[3] == parts[3].lowercased() else { continue }
            token = parts[3]
            return
        }
        return nil
    }

    /// The state file from where the chat left it: the last `session` line's transcript is the history (a new one
    /// after `/new`, `/fork` or `/resume` starts it again); the other lines are the phase. No session after 10 s: a
    /// problem.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        chat.recorded = kept.phase
        await chat.followSessions(Self.state(token), on: exec, late: true, read: { [kept] line, history in
            kept.transcript.read(line, end: chat.marks[chat.source ?? ""]?.offset ?? 0, into: &history)
        }, restarted: { [kept] in kept.transcript = PiTranscript() }, line: { read($0, chat) })
    }

    /// A state line: the phase it says, and a session line's transcript.
    @MainActor private func read(_ object: [String: Any], _ chat: Chat) -> String? {
        var session: String?
        switch object["type"] as? String {
        case "session":
            guard let source = object["path"] as? String else { return nil }
            kept.phase = .ready
            if source != chat.source {
                kept.transcript = PiTranscript()
            }
            session = source
        case "tree":
            kept.transcript.tree(object["leaf"] as? String, at: object["at"] as? Int ?? 0, into: &chat.history)
        case "blocked":
            kept.beforeDialog = kept.phase == .waiting ? kept.beforeDialog : kept.phase
            kept.phase = .waiting
        case "unblocked": kept.phase = kept.beforeDialog
        case let type?:
            // `shutdown`: between sessions (`/new`) or gone, nothing is sent.
            guard let phase = ["working": Chat.Phase.working, "idle": .ready, "shutdown": .starting][type] else {
                return nil
            }
            kept.phase = phase
        case nil: return nil
        }
        chat.recorded = kept.phase
        return session
    }
}
