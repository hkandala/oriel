import AppKit
import HerdrKit

/// The commands of `oriel` that Oriel answers (agent-control/cli). A track adds a command in its own file as a
/// `static let` on `AgentCommand` and one line in `AgentCommands.all`; its usage and help live with it.
struct AgentCommand {
    let name: String
    /// The synopsis after `oriel`, the name first: `float <pane> [--on-top]`.
    let usage: String
    /// One line for `oriel help`.
    let summary: String
    /// More lines for `oriel help <name>`, if any.
    var help = ""
    /// Reads its arguments off the call (`flag`, `value`, `argument`, then `done`), acts and answers. Any error that
    /// is not an `AgentError` answers `failed` with its text.
    let run: @MainActor (inout AgentCall) async throws -> AgentOutput
}

@MainActor
enum AgentCommands {
    /// The commands, in `oriel help`'s order.
    static let all: [AgentCommand] = [
        .help,
        .info,
        .float,
        .unfloat,
        .copy,
        .plugins,
        .open,
        .reveal,
        .card,
        .shown,
        .notify,
        .agent,
        .chat,
    ]

    /// The script Oriel writes to `~/.cache/oriel/bin/oriel` on each machine it opens a session on.
    static let script = Bundle.main.url(forResource: "oriel", withExtension: "sh").flatMap { try? Data(contentsOf: $0) }

    /// Parses the arguments, runs the command against the asking session's store and makes its answer: what goes to
    /// standard output (text, or JSON with `--json`), the exit code and the text for standard error.
    static func run(_ argv: [String], cwd: String, from pane: String, request id: String,
                    store: HostStore) async -> AgentAnswer
    {
        let json = argv.contains("--json")
        var call = AgentCall(store: store, pane: pane, cwd: cwd, id: id, args: argv.filter { $0 != "--json" })
        do {
            // No arguments: help.
            let name = call.args.isEmpty ? "help" : call.args.removeFirst()
            guard let command = all.first(where: { $0.name == name }) else {
                throw AgentError.unknownCommand(name)
            }
            let output = try await command.run(&call)
            return AgentAnswer(code: 0, out: json ? output.jsonData : Data(output.text.utf8), err: "")
        } catch {
            return failure(error, json: json)
        }
    }

    /// The answer for an error: `oriel: ‹message›` on standard error, and with `--json` the error as JSON too.
    static func failure(_ error: Error, json: Bool) -> AgentAnswer {
        let error = error as? AgentError ?? AgentError(code: "failed", message: error.localizedDescription)
        let out = json ? AgentOutput(["error": ["code": error.code, "message": error.message]]).jsonData : Data()
        return AgentAnswer(code: error.exit, out: out, err: "oriel: \(error.message)\n")
    }
}

/// What goes back to the command: its exit code, its standard output and its standard error.
struct AgentAnswer {
    let code: Int32
    let out: Data
    let err: String
}

/// An error code and message of agent-control/protocol, Error codes.
struct AgentError: Error {
    let code: String
    let message: String

    var exit: Int32 {
        ["usage", "unknown_command", "protocol"].contains(code) ? 2 : 1
    }

    static func usage(_ message: String) -> AgentError {
        AgentError(code: "usage", message: message)
    }

    static func paneNotFound(_ id: String, in session: String) -> AgentError {
        AgentError(code: "pane_not_found", message: "pane \(id) is not in herdr session \(session)")
    }

    static func noWindow(_ session: String) -> AgentError {
        AgentError(code: "failed", message: "no window shows herdr session \(session)")
    }

    static func unknownCommand(_ name: String) -> AgentError {
        AgentError(code: "unknown_command", message: "no command \(name); `oriel help` lists them")
    }
}

/// A command's answer: one JSON value for `--json`, and the text without it.
struct AgentOutput {
    /// Made of dictionaries, arrays, strings, numbers, booleans and `NSNull`.
    let json: Any
    let text: String

    /// Without a text, a dictionary's fields as `name: value` lines.
    init(_ json: Any, text: String? = nil) {
        self.json = json
        self.text = text ?? (json as? [String: Any] ?? [:]).sorted { $0.key < $1.key }.map { key, value in
            "\(key): \((value as? [Any])?.map { "\($0)" }.joined(separator: ", ") ?? "\(value)")\n"
        }.joined()
    }

    /// Keys sorted, so an answer reads the same every time.
    var jsonData: Data {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]))
        return (data ?? Data("null".utf8)) + Data("\n".utf8)
    }
}

/// One request as a command sees it: who asks, and the arguments it has not read yet.
@MainActor
struct AgentCall {
    /// The asking pane's session.
    let store: HostStore
    /// The asking pane.
    let pane: String
    /// The command's working folder on the asking pane's machine.
    let cwd: String
    /// The request's id, which names its files in the machine's mailbox.
    let id: String
    var args: [String]

    /// Whether the option is there, every copy of it read.
    mutating func flag(_ name: String) -> Bool {
        let had = args.contains(name)
        args.removeAll { $0 == name }
        return had
    }

    /// The value after the option (`--beside w1:p3`), or nil without the option.
    mutating func value(_ name: String) throws -> String? {
        guard let index = args.firstIndex(of: name) else { return nil }
        guard index + 1 < args.count else { throw AgentError.usage("\(name) needs a value") }
        defer { args.removeSubrange(index ... index + 1) }
        return args[index + 1]
    }

    /// The next argument, which must be there; `name` says which in the error.
    mutating func argument(_ name: String) throws -> String {
        guard let next = try optionalArgument() else { throw AgentError.usage("missing <\(name)>") }
        return next
    }

    /// The next argument, nil when none is left.
    mutating func optionalArgument() throws -> String? {
        guard let next = args.first else { return nil }
        guard !next.hasPrefix("--") else { throw AgentError.usage("unknown option \(next)") }
        return args.removeFirst()
    }

    /// Every argument was read: one left over is a usage error.
    func done() throws {
        guard let extra = args.first else { return }
        throw AgentError.usage(extra.hasPrefix("--") ? "unknown option \(extra)" : "extra argument \(extra)")
    }

    /// A pane argument: `w1:p3` in the asking session, or `‹session›/‹pane›` of a session on the same machine. The
    /// machine is always the asking pane's, so no argument can reach another one.
    func target(_ argument: String) throws -> PaneTarget {
        let parts = argument.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let (session, id) = parts.count == 2 ? (parts[0], parts[1]) : (store.session, argument)
        guard !id.isEmpty, !id.hasPrefix("-"), !id.contains("/"), Session.isValidName(session),
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw AgentError(code: "bad_argument", message: "\(argument) is not a pane") }
        guard session == store.session || store.sessions.contains(where: { $0.name == session && $0.running }) else {
            throw AgentError(
                code: "pane_not_found",
                message: "no herdr session \(session) runs on \(store.machine.name)",
            )
        }
        let target = PaneTarget(session: session, id: id, machine: store.machine)
        if let found = target.store, found.state == .live, found.pane(id) == nil {
            throw AgentError.paneNotFound(id, in: session)
        }
        return target
    }
}

/// A pane that a command names, on the asking pane's machine.
@MainActor
struct PaneTarget {
    let session: String
    let id: String
    let machine: Machine

    /// Its session's store, when Oriel follows it.
    var store: HostStore? {
        HostStore.all.first { $0.session == session && $0.machine.id == machine.id }
    }
}

extension AgentCommand {
    static let help = AgentCommand(
        name: "help", usage: "help [<command>]", summary: "Lists the commands, or tells more of one",
    ) { call in
        let name = try call.optionalArgument()
        try call.done()
        // `status` too, which the script answers by itself.
        let all = [.status] + AgentCommands.all
        if let name {
            guard let command = all.first(where: { $0.name == name }) else {
                throw AgentError.unknownCommand(name)
            }
            let text = "usage: oriel \(command.usage)\n\n\(command.summary).\n"
                + (command.help.isEmpty ? "" : "\n\(command.help)\n")
            return AgentOutput(["name": command.name, "usage": command.usage, "summary": command.summary,
                                "help": command.help], text: text)
        }
        let commands = all.map { ($0.usage, $0.summary) }
        let width = commands.map(\.0.count).max() ?? 0
        let text = """
        usage: oriel [--pane <pane>] [--timeout <seconds>] <command> [<args>] [--json]

        \(commands.map { "  " + $0.padding(toLength: width + 2, withPad: " ", startingAt: 0) + $1 }
            .joined(separator: "\n"))

        A <pane> is w1:p3 in this session, or <session>/<pane> on this machine. `oriel help <command>` tells more.

        """
        return AgentOutput(["commands": all.map {
            ["name": $0.name, "usage": $0.usage, "summary": $0.summary]
        }], text: text)
    }

    /// Only for `help`: the script answers it from herdr's tokens and never sends it.
    static let status = AgentCommand(
        name: "status", usage: "status [--json | --watch]", summary: "Says if Oriel shows this pane, from herdr alone",
        help: "Exit 0 when an Oriel follows the session, 3 when none does. --watch prints a line on each change.",
    ) { _ in throw AgentError.usage("the script answers status") }

    static let info = AgentCommand(
        name: "info", usage: "info", summary: "What this Oriel offers: version, protocol, commands, agents",
    ) { call in
        try call.done()
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return AgentOutput([
            "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "protocol": AgentRequest.version,
            "machine": call.store.machine.name,
            "appearance": dark ? "dark" : "light",
            "commands": AgentCommands.all.map(\.name),
            // A key path to a metatype's static property crashes Swift 6.4.2's SIL generation.
            // swiftformat:disable:next preferKeyPath
            "agents": ChatAdapters.all.map { $0.command },
        ])
    }
}
