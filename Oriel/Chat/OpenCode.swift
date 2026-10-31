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
    static let stopKeys = ["escape", "escape"]
    static let quit = "/exit"

    static func flags(_ token: String, resume: String?) -> String {
        (resume.map { $0 + " " } ?? "") + "--port 0 --hostname 127.0.0.1 -- oriel-\(token)"
    }

    static func resume(_ session: String) -> String? {
        isID(session) ? "--session \(session)" : nil
    }

    /// Writes the plugin and its `tui.json` (each whole, then renamed: another pane may be starting) and the launch's
    /// password, then gives the line: the password goes from its file into the environment, never into argv or the
    /// scrollback. The line reads the same in sh, bash, zsh and fish (3.4 and later).
    /// ponytail: a home folder with a `"` breaks `tui.json`; escape it if one shows up. A pane running for 30 days
    /// loses its password file to the sweep (the chat says the server did not answer); touch it while followed if that
    /// matters.
    static func prepare(_ token: String, resume: String?, on exec: any Exec) async -> String? {
        let script = #"""
        umask 077; c=$HOME/.cache/oriel; d=$c/chat/$1; p=$c/opencode/oriel-tui.js
        mkdir -p "$c/opencode" "$d" && cat >"$p.$$" && mv "$p.$$" "$p" && t=$c/opencode/tui.json &&
        printf '{"plugin":["%s"]}\n' "$p" >"$t.$$" && mv "$t.$$" "$t" &&
        od -An -tx1 -N16 /dev/urandom | tr -d ' \n' >"$d/pw" || exit 1
        \#(ChatAdapters.sweep); exit 0
        """#
        guard await exec.succeeds(script, [token], input: plugin.split(separator: "\n").map(String.init)) else {
            return nil
        }
        let folder = "$HOME/.cache/oriel/chat/\(token)"
        return "ORIEL_OC_STATE=\(folder)/state.jsonl OPENCODE_TUI_CONFIG=$HOME/.cache/oriel/opencode/tui.json "
            + "OPENCODE_SERVER_PASSWORD=$(cat \"\(folder)/pw\") \(command) \(flags(token, resume: resume))"
    }

    /// The server's address comes from the SDK client's private `_client`: check it on each opencode release.
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
        guard let (token, pids) = ChatAdapters.marked(foreground, { argv in
            guard argv.contains("--port"), let marker = argv.after("--"), marker.hasPrefix("oriel-") else { return nil }
            return ChatAdapters.token(marker.dropFirst(6))
        }) else { return nil }
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
        for await batch in lines {
            for line in batch where !Task.isCancelled {
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
    }

    /// The session's history once the event stream is connected (so nothing falls between the two), the waiting
    /// requests, then every event: parts, the turn's status, requests asked and answered.
    @MainActor private func server(_ chat: Chat, _ url: String, _ id: String, _ waits: Waits,
                                   _ exec: any Exec) async
    {
        guard let events = try? await exec.openCodeEvents(url, folder: folder) else { return }
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
        await waits.load(url, folder, exec, chat)
        while let line = await lines.next() {
            guard line.hasPrefix("data: ") else { continue }
            let (changed, waited) = await Self.apply(line, to: session)
            // Cancelled: the stream dropped, or another session's took over meanwhile.
            guard !Task.isCancelled else { return }
            if let changed {
                session = changed
                chat.history = changed.history
            }
            // Read here again only for the waits (its JSON objects are not Sendable).
            if waited, let event = Self.event(line), waits.take(event, session: id, url: url) {
                waits.publish(chat)
            }
        }
    }

    /// An event's line applied to the session off the main actor (it builds the history again whole: OpenCodeSession's
    /// ponytail): the session when it changed, and whether the event is one the waits read.
    private static func apply(_ line: String, to session: OpenCodeSession) async -> (OpenCodeSession?, Bool) {
        await Task.detached {
            var session = session
            let event = Self.event(line)
            let changed = event.map { session.apply($0) } == true
            return (changed ? session : nil, (event?["type"] as? String).map(Waits.reads) == true)
        }.value
    }

    /// An event's object from its `data:` line.
    private nonisolated static func event(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8.dropFirst(6))) as? [String: Any]
    }

    /// The session's history, else a problem.
    @MainActor private func history(_ chat: Chat, _ url: String, _ id: String,
                                    _ exec: any Exec) async -> OpenCodeSession?
    {
        // The empty chat shows the loader meanwhile, as for a history file.
        chat.loading = true
        defer { chat.loading = false }
        let answer = await exec.openCode(url, "/session/\(id)/message", folder: folder)
        guard !Task.isCancelled else { return nil }
        let session = await Task.detached { [answer] in
            var session = OpenCodeSession(id: id)
            return answer?.status == 200 && session.load(answer?.body ?? "") ? session : nil
        }.value
        guard !Task.isCancelled else { return nil }
        guard let session else {
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

    /// A request already answered in the TUI gets a 404: its `replied` event takes the card away.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async -> Bool {
        guard let request = try? JSONSerialization.jsonObject(with: question.raw) as? [String: String],
              let kind = request["kind"], let id = request["id"], let url = request["url"]
        else { return false }
        let body: Any = kind == "permission"
            ? ["reply": Self.replies.first { $0.0 == answers.values.first }?.1 ?? "reject"]
            : ["answers": question.items.map { [answers[$0.text] ?? ""] }]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let status = await exec.openCode(url, "/\(kind)/\(id)/reply", body: String(decoding: data, as: UTF8.self),
                                               folder: folder)?.status else { return false }
        return (200 ..< 300).contains(status) || status == 404
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
            items = ChatQuestion.items(request["questions"] as? [[String: Any]] ?? [], several: "multiple") ?? []
        }
        let raw = try? JSONSerialization.data(withJSONObject: ["kind": kind, "id": id, "url": url])
        requests.append((id, items.isEmpty ? nil : raw.map { ChatQuestion(items: items, raw: $0) }))
        // By time: the ids after their kind's prefix.
        requests.sort { $0.id.dropFirst(4) < $1.id.dropFirst(4) }
    }

    /// The requests that wait now, all at once (a publish meanwhile keeps the old ones), then published. A status
    /// before the stream dropped may be old; a card answered before (the answer may be lost) is new again.
    func load(_ url: String, _ folder: String, _ exec: any Exec, _ chat: Chat) async {
        busy = nil
        defer {
            fresh = true
            if !Task.isCancelled {
                publish(chat)
            }
        }
        var lists: [(String, [[String: Any]])] = []
        for kind in ["permission", "question"] {
            let body = await exec.openCode(url, "/\(kind)", folder: folder)?.body ?? ""
            lists.append((kind, (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [[String: Any]] ?? []))
        }
        requests = []
        for (kind, list) in lists {
            for request in list {
                add(kind, request, url)
            }
        }
    }

    /// The events `take` reads.
    nonisolated static func reads(_ type: String) -> Bool {
        type.hasPrefix("permission.") || type.hasPrefix("question.") || ["session.status", "session.idle"]
            .contains(type)
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
