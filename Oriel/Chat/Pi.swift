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
    let stopKeys = ["escape"]
    /// Kept with the chat, which keeps its adapter: what a follow that starts again goes on from.
    private let kept = Kept()

    @MainActor private final class Kept {
        var transcript = PiTranscript()
        var phase = Chat.Phase.starting
        /// The phase a dialog interrupted, back when it closes.
        var beforeDialog = Chat.Phase.ready
        /// `/tree` moves the transcript has not been read up to: the leaf, from that size of the file on.
        var moves: [(leaf: String?, at: Int)] = []

        nonisolated init() {}

        /// The moves the transcript has been read up to.
        func move(upTo offset: Int, _ history: inout ChatHistory) {
            while let move = moves.first, move.at <= offset {
                moves.removeFirst()
                transcript.move(to: move.leaf, into: &history)
            }
        }
    }

    /// The extension, and its file on the machine, named by its content: two versions of Oriel never fight over one.
    private static let source = Bundle.main.url(forResource: "pi-oriel", withExtension: "ts")
        .flatMap { try? Data(contentsOf: $0) }
    private static let file = source.map { source in
        ".cache/oriel/pi-oriel-" + SHA256.hash(data: source).prefix(4).map { String(format: "%02x", $0) }.joined()
            + ".ts"
    }

    /// Under the home folder of the pane's machine, beside Claude Code's side files (the same 30-day sweep).
    private var state: String {
        ".cache/oriel/chat/\(token)/pi.jsonl"
    }

    static func flags(_ token: String) -> String {
        "-e ~/\(file ?? "") --oriel ~/.cache/oriel/chat/\(token)/pi.jsonl"
    }

    /// One run writes the extension (whole: a temporary file, then a rename) and the launch's folder, and sweeps the
    /// launches' folders untouched for 30 days. pi exits at once when `-e` names no file: no chat then.
    static func prepare(_ token: String, on exec: any Exec) async -> String? {
        guard let source, let file else { return nil }
        let script = #"""
        umask 077; d=$HOME/.cache/oriel; f=$HOME/$1
        mkdir -p "$d/chat/$2" && chmod 700 "$d" && cat >"$f.$$" && mv "$f.$$" "$f" || exit 1
        find "$d/chat" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null; exit 0
        """#
        guard let channel = try? await exec.run(["sh", "-c", script, "sh", file, token]) else { return nil }
        channel.write(String(decoding: source, as: UTF8.self))
        channel.closeInput()
        return await channel.exit().status == 0 ? command + " " + flags(token) : nil
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
        var transcript: Task<Void, Never>?
        defer { transcript?.cancel() }
        let follow = { [kept] (source: String) in
            transcript?.cancel()
            transcript = Task {
                await chat.follow(history: source, on: exec) { line, history in
                    let read = kept.transcript.read(line, into: &history)
                    kept.move(upTo: chat.marks[source]?.offset ?? 0, &history)
                    return read
                }
            }
        }
        if let source = chat.source {
            follow(source)
        }
        let late = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled, chat.source == nil {
                chat.problem = "Pi has not started a session"
            }
        }
        defer { late.cancel() }
        guard let lines = try? await exec.follow(state, from: chat.marks[state] ?? FileMark()) else { return }
        // Lines buffered before a cancel still come: not into the next follow's chat.
        for await line in lines where !Task.isCancelled {
            guard case let .line(text, mark) = line else { continue }
            chat.marks[state] = mark
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                continue
            }
            if let source = read(object, chat) {
                follow(source)
            }
        }
    }

    /// A state line: the phase it says, and the transcript to follow when the session changed.
    @MainActor private func read(_ object: [String: Any], _ chat: Chat) -> String? {
        var changed: String?
        switch object["type"] as? String {
        case "session":
            guard let source = object["path"] as? String else { return nil }
            chat.problem = nil
            kept.moves = []
            kept.phase = .ready
            if source != chat.source {
                chat.source = source
                chat.marks[source] = nil
                kept.transcript = PiTranscript()
                chat.history = ChatHistory()
                changed = source
            }
        case "tree":
            // pi writes nothing on /tree: the leaf moves once the transcript is read up to its size then.
            kept.moves.append((object["leaf"] as? String, object["at"] as? Int ?? 0))
            if let source = chat.source {
                kept.move(upTo: chat.marks[source]?.offset ?? 0, &chat.history)
            }
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
        return changed
    }
}
