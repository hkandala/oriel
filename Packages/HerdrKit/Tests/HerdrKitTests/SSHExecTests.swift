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
