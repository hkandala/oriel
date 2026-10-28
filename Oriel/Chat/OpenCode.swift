import Foundation
import HerdrKit

/// OpenCode 1.x (resources/research/agents/opencode.md). Started with its server on (`--port 0 --hostname 127.0.0.1`),
/// a password from a 0600 file, and Oriel's TUI plugin (`OPENCODE_TUI_CONFIG`), which appends the server's address,
/// the TUI's session and whether a dialog is open to `~/.cache/oriel/chat/T/state.jsonl`. The history is the server's,
/// then its event stream; its permissions and questions are answered in the chat. The marker is `-- oriel-T` after
/// the flags (opencode ignores what follows `--`), and the state line's pid must be the marked process's.
struct OpenCode: ChatAdapter {
    static let command = "opencode"
    let token: String
    let pids: [Int]
    /// The first Esc only arms the interrupt.
    let stopKeys = ["escape", "escape"]

    var folder: String {
        ".cache/oriel/chat/\(token)"
    }

    static func flags(_ token: String) -> String {
        "--port 0 --hostname 127.0.0.1 -- oriel-\(token)"
    }

    /// Writes the plugin and its `tui.json` (each whole, then renamed: another pane may be starting) and the launch's
    /// password, then gives the line: the password goes from its file into the environment, never into argv or the
    /// scrollback. The line reads the same in sh, bash, zsh and fish (3.4 and later).
    /// Side files untouched for 30 days go, as Claude Code's hook does.
    /// ponytail: a home folder with a `"` breaks `tui.json`; escape it if one shows up. A pane running for 30 days
    /// loses its password file then (the chat says the server did not answer); touch it while followed if that matters.
    static func prepare(_ token: String, on exec: any Exec) async -> String? {
        let script = #"""
        umask 077; c=$HOME/.cache/oriel; d=$c/chat/$1; p=$c/opencode/oriel-tui.js
        mkdir -p "$c/opencode" "$d" && cat >"$p.$$" && mv "$p.$$" "$p" && t=$c/opencode/tui.json &&
        printf '{"plugin":["%s"]}\n' "$p" >"$t.$$" && mv "$t.$$" "$t" &&
        od -An -tx1 -N16 /dev/urandom | tr -d ' \n' >"$d/pw" || exit 1
        find "$c/chat" -mindepth 2 -mtime +30 -delete 2>/dev/null
        find "$c/chat" -mindepth 1 -type d -empty -mmin +1 -delete 2>/dev/null; exit 0
        """#
        guard let channel = try? await exec.run(["sh", "-c", script, "sh", token]) else { return nil }
        for line in plugin.split(separator: "\n") {
            channel.write(String(line))
        }
        channel.closeInput()
        guard await channel.exit().status == 0 else { return nil }
        let folder = "$HOME/.cache/oriel/chat/\(token)"
        return "ORIEL_OC_STATE=\(folder)/state.jsonl OPENCODE_TUI_CONFIG=$HOME/.cache/oriel/opencode/tui.json "
            + "OPENCODE_SERVER_PASSWORD=$(cat \"\(folder)/pw\") \(command) \(flags(token))"
    }

    /// The TUI plugin: one line whenever the session, a dialog or the server changes, checked every 200 ms. The
    /// server's address comes from the SDK client's private `_client`: check it on each opencode release.
    static let plugin = #"""
    // Oriel's TUI plugin: one JSON line to $ORIEL_OC_STATE whenever the session, a dialog or the server changes.
    import { appendFileSync } from "node:fs"
    export default {
      id: "oriel.state",
      tui: async (api) => {
        const file = process.env.ORIEL_OC_STATE
        if (!file) return
        let last = ""
        const tick = () => {
          const route = api.route.current
          const config = api.client?._client?.getConfig?.() ?? api.client?.client?.getConfig?.()
          const line = JSON.stringify({ pid: process.pid, url: config?.baseUrl ?? null,
            session: route?.name === "session" ? route.params?.sessionID ?? null : null, dialog: api.ui.dialog.open })
          // A plugin must never break its host: a removed folder only ends the reports.
          if (line !== last) { last = line; try { appendFileSync(file, line + "\n") } catch {} }
        }
        tick()
        const timer = setInterval(tick, 200)
        api.lifecycle.onDispose(() => clearInterval(timer))
      },
    }
    """#

    init?(_ foreground: [Program.Foreground]) {
        var token: String?, pids: [Int] = []
        for process in foreground {
            guard process.argv.contains("--port"), let dashes = process.argv.firstIndex(of: "--"),
                  dashes + 1 < process.argv.count, process.argv[dashes + 1].hasPrefix("oriel-") else { continue }
            let id = String(process.argv[dashes + 1].dropFirst(6))
            guard UUID(uuidString: id) != nil, id == id.lowercased(), token == nil || token == id else { continue }
            token = id
            pids.append(process.pid)
        }
        guard let token else { return nil }
        self.token = token
        self.pids = pids
    }

    /// The state file: each new server or session loads its history and follows its events. No state line after
    /// 15 s (the company build ignores the plugin): the card shows its terminal.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        let waits = Waits()
        var server: Task<Void, Never>?, current: String?
        defer { server?.cancel() }
        let late = Task {
            try? await Task.sleep(for: .seconds(15))
            // Once: a user who went back to the chat stays there.
            if !Task.isCancelled, chat.source == nil, chat.problem != Self.unreported {
                chat.problem = Self.unreported
                chat.showsChat = false
            }
        }
        defer { late.cancel() }
        // From the start each time: the last line holds the server and session.
        guard let lines = try? await exec.follow(folder + "/state.jsonl", from: FileMark()) else { return }
        for await line in lines where !Task.isCancelled {
            guard case let .line(text, _) = line,
                  let state = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let pid = state["pid"] as? Int, pids.contains(pid),
                  let url = state["url"] as? String, url.wholeMatch(of: /http:\/\/127\.0\.0\.1:[0-9]{1,5}/) != nil
            else { continue }
            let session = (state["session"] as? String).flatMap { Self.isID($0) ? $0 : nil }
            if chat.problem == Self.unreported {
                chat.problem = nil
            }
            waits.dialog = state["dialog"] as? Bool == true
            let source = url + " " + (session ?? "")
            if current != source {
                current = source
                server?.cancel()
                waits.requests = []
                waits.busy = nil
                // Another session starts empty; the same one shown again keeps its rows until the reload.
                if chat.source != source {
                    chat.history = ChatHistory()
                    chat.source = source
                    chat.problem = chat.problem?.hasPrefix(Self.serverProblem) == true ? nil : chat.problem
                }
                server = session.map { session in
                    Task {
                        // Again after a dropped event stream, until the server or session changes.
                        while !Task.isCancelled {
                            await self.server(chat, url, session, waits, exec)
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            }
            waits.publish(chat)
        }
    }

    /// The session's history once the event stream is connected (so nothing falls between the two), the waiting
    /// requests, then every event: parts, the turn's status, requests asked and answered.
    @MainActor private func server(_ chat: Chat, _ url: String, _ id: String, _ waits: Waits,
                                   _ exec: any Exec) async
    {
        guard let events = try? await exec.openCodeEvents(url, password: folder) else { return }
        var lines = events.makeAsyncIterator(), connected = false
        while !connected, let line = await lines.next() {
            connected = line.contains(#""server.connected""#)
        }
        guard !Task.isCancelled else { return }
        guard connected else {
            chat.problem = Self.serverProblem + " did not answer"
            return
        }
        guard var session = await history(chat, url, id, exec) else { return }
        chat.history = session.history
        // A status before the stream dropped may be old; a card answered before (the answer may be lost) is new again.
        waits.busy = nil
        await waits.load(url, folder, exec)
        waits.fresh = true
        guard !Task.isCancelled else { return }
        waits.publish(chat)
        while let line = await lines.next(), !Task.isCancelled {
            guard line.hasPrefix("data: "),
                  let event = try? JSONSerialization.jsonObject(with: Data(line.utf8.dropFirst(6))) as? [String: Any]
            else { continue }
            if session.apply(event) {
                chat.history = session.history
            }
            if waits.take(event, session: id, url: url) {
                waits.publish(chat)
            }
        }
    }

    /// The session's history, else a problem.
    @MainActor private func history(_ chat: Chat, _ url: String, _ id: String,
                                    _ exec: any Exec) async -> OpenCodeSession?
    {
        let answer = await exec.openCode(url, "/session/\(id)/message", password: folder)
        guard !Task.isCancelled else { return nil }
        var session = OpenCodeSession(id: id)
        guard let answer, answer.status == 200, session.load(answer.body) else {
            chat.problem = Self.serverProblem + " did not give the session" + (answer.map { " (\($0.status))" } ?? "")
            return nil
        }
        if chat.problem?.hasPrefix(Self.serverProblem) == true {
            chat.problem = nil
        }
        return session
    }

    /// A slow first start (opencode installs its plugin packages first) may still report: the chat goes on then.
    static let unreported = "OpenCode has not reported its session"
    static let serverProblem = "OpenCode's server"

    /// opencode's ids (`ses_…`, `per_…`, `que_…`) as they go into a URL.
    static func isID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// The permission card's buttons, as the TUI names them, and the replies they send.
    static let replies = [("Allow once", "once"), ("Allow always", "always"), ("Reject", "reject")]

    /// A request already answered in the TUI gets a 404; its `replied` event took the card away.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async {
        guard let request = try? JSONSerialization.jsonObject(with: question.raw) as? [String: String],
              let kind = request["kind"], let id = request["id"], let url = request["url"]
        else { return }
        let body: Any = kind == "permission"
            ? ["reply": Self.replies.first { $0.0 == answers.values.first }?.1 ?? "reject"]
            : ["answers": question.items.map { [answers[$0.text] ?? ""] }]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        _ = await exec.openCode(url, "/\(kind)/\(id)/reply", body: String(decoding: data, as: UTF8.self),
                                password: folder)
    }
}

/// What the chat shows while OpenCode waits: a dialog (pickers: the terminal), its permission and question
/// requests (the oldest as a card), and whether its turn runs.
@MainActor private final class Waits {
    var dialog = false
    var busy: Bool?
    /// The next publish shows the card again, even the same request's.
    var fresh = false
    var requests: [(id: String, question: ChatQuestion?)] = []

    /// Its card: a permission's three replies, or a question's options (one answer each: else the terminal).
    func add(_ kind: String, _ request: [String: Any], _ url: String) {
        guard let id = request["id"] as? String, OpenCode.isID(id), !requests.contains(where: { $0.id == id })
        else { return }
        var items: [ChatQuestion.Item] = []
        if kind == "permission" {
            let metadata = request["metadata"] as? [String: Any]
            let target = metadata?["command"] as? String
                ?? (request["patterns"] as? [String] ?? []).joined(separator: ", ")
            let name = (request["permission"] as? String ?? "tool").capitalized
            items = [ChatQuestion.Item(text: target.isEmpty ? name : "\(name): \(target)",
                                       options: OpenCode.replies.map(\.0))]
        } else {
            let questions = request["questions"] as? [[String: Any]] ?? []
            if !questions.contains(where: { $0["multiple"] as? Bool == true }) {
                items = questions.map { question in
                    ChatQuestion.Item(text: question["question"] as? String ?? "",
                                      options: (question["options"] as? [[String: Any]] ?? [])
                                          .compactMap { $0["label"] as? String })
                }
            }
        }
        let usable = !items.isEmpty && items.allSatisfy { !$0.options.isEmpty }
        let raw = try? JSONSerialization.data(withJSONObject: ["kind": kind, "id": id, "url": url])
        requests.append((id, usable ? raw.map { ChatQuestion(items: items, raw: $0) } : nil))
        // By time: the ids after their kind's prefix.
        requests.sort { $0.id.dropFirst(4) < $1.id.dropFirst(4) }
    }

    /// The requests that wait now, all at once: a publish meanwhile keeps the old ones.
    func load(_ url: String, _ folder: String, _ exec: any Exec) async {
        var lists: [(String, [[String: Any]])] = []
        for kind in ["permission", "question"] {
            let body = await exec.openCode(url, "/\(kind)", password: folder)?.body ?? ""
            lists.append((kind, (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [[String: Any]] ?? []))
        }
        requests = []
        for (kind, list) in lists {
            for request in list {
                add(kind, request, url)
            }
        }
    }

    /// An event's news for the waits: the turn's status, a request asked or answered.
    func take(_ event: [String: Any], session id: String, url: String) -> Bool {
        let properties = event["properties"] as? [String: Any] ?? [:]
        let own = properties["sessionID"] as? String == id
        switch event["type"] as? String {
        case "session.status" where own:
            busy = (properties["status"] as? [String: Any])?["type"] as? String != "idle"
        case "session.idle" where own: busy = false
        case "permission.asked": add("permission", properties, url)
        case "question.asked": add("question", properties, url)
        case "permission.replied", "question.replied", "question.rejected":
            requests.removeAll { $0.id == properties["requestID"] as? String }
        default: return false
        }
        return true
    }

    /// Waiting while a dialog or a request is open; working while the turn runs; else herdr's status.
    func publish(_ chat: Chat) {
        let phase: Chat.Phase? = dialog || !requests.isEmpty ? .waiting : busy == true ? .working : nil
        // Only a change: Observation reports equal writes too.
        if chat.recorded != phase {
            chat.recorded = phase
        }
        let question = dialog ? nil : requests.first?.question
        if fresh || chat.question?.raw != question?.raw {
            chat.question = question
            fresh = false
        }
    }
}
