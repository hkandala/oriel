import Foundation
@testable import HerdrKit
import Testing

/// The envelope runs in the remote login shell; `sh` here stands in for it.
@Test func `envelope runs the argv unchanged`() async throws {
    let argv = ["printf", "%s|", "it's", "a b", "$HOME", "\"q\"", "`x`", "ü\n2"]
    let exec = await ProcessExec()
    let out = try await exec.output(["sh", "-c", SSHExec.envelope(argv)])
    #expect(out == "it's|a b|$HOME|\"q\"|`x`|ü\n2|")
}

@Test func `targets that are not options`() {
    #expect(SSHExec.isValidTarget("user@devbox"))
    #expect(!SSHExec.isValidTarget("-oProxyCommand=x"))
    #expect(!SSHExec.isValidTarget("a b"))
    #expect(!SSHExec.isValidTarget(""))
}

/// The relay here, without ssh: runs at once over one process, their stdin, exits and kills.
@Test func `relay carries runs over one process`() async throws {
    let local = await ProcessExec()
    let relay = try #require(await Relay.start(ProcessExec.spawn(["perl", "-e", Relay.script], local.environment)))
    let failing = try relay.run("echo out; echo err >&2; exit 3")
    let echo = try relay.run("cat")
    let sleeping = try relay.run("sleep 100")
    echo.write(#"{"a": "b c"}"#)
    echo.closeInput()
    #expect(await echo.lines.reduce([]) { $0 + [$1] } == [#"{"a": "b c"}"#])
    #expect(await echo.exit() == (0, ""))
    #expect(await failing.lines.reduce([]) { $0 + [$1] } == ["out"])
    #expect(await failing.exit() == (3, "err\n"))
    sleeping.terminate()
    #expect(await sleeping.exit().status == 9)
}
