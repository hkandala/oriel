import HerdrKit
import OSLog

/// The `oriel` command's requests (agent-control/protocol): heard on the session's events stream, taken from the
/// machine's mailbox, run, answered there.
extension HostStore {
    private static let log = Logger(subsystem: "dev.hkandala.oriel", category: "agent")

    /// One request: an Oriel whose user is away gives the one in use 500 ms to take it first. Nothing when another
    /// Oriel took it, or the command gave up.
    func answer(request id: String, from pane: String) async {
        if away {
            try? await Task.sleep(for: .milliseconds(500))
        }
        let exec = await machine.exec()
        guard let data = try? await exec.take(request: id) else { return }
        let answer: AgentAnswer
        do {
            let request = try AgentRequest(data)
            answer = await AgentCommands.run(request.argv, cwd: request.cwd, from: pane, request: id, store: self)
        } catch let .newer(version) {
            answer = AgentCommands.failure(AgentError(code: "protocol", message: """
            the request speaks protocol \(version); this Oriel speaks \(AgentRequest.version)
            """), json: false)
        } catch {
            let why = "not a request of protocol \(AgentRequest.version), or over 64 KiB or 64 fields"
            answer = AgentCommands.failure(AgentError.usage(why), json: false)
        }
        do {
            try await exec.answer(request: id, code: answer.code, out: answer.out, err: answer.err)
        } catch {
            // The command exits 4.
            Self.log.error("answer to \(id) failed: \(error.localizedDescription)")
        }
    }
}
