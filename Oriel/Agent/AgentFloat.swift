import AppKit
import HerdrKit

extension AgentCommand {
    static let float = AgentCommand(
        name: "float", usage: "float <pane> [--on-top]", summary: "Floats a pane in a window of its own",
        help: """
        Over the window where the user last worked in the asking session. A pane that floats already comes to the \
        front ("existing": true). --on-top turns on Stay on Top.
        """,
    ) { call in
        let onTop = call.flag("--on-top")
        let target = try call.target(call.argument("pane"))
        try call.done()
        let machine = call.store.machine
        guard let window = call.store.windows.first else {
            throw AgentError(code: "failed", message: "no window shows herdr session \(call.store.session)")
        }
        let existing = target.floating != nil
        WindowPages.float(session: target.session, pane: target.id, machine: machine.id, over: window, agent: true)
        // A session with no page opens a float-only one, which floats the pane once it connects.
        var floating = target.floating
        let end = ContinuousClock.now + .seconds(8)
        while floating == nil, window.floatPending != nil, end > .now {
            try await Task.sleep(for: .milliseconds(50))
            floating = target.floating
        }
        if floating == nil, case let .failed(error) = target.store?.state {
            throw error
        }
        guard let (page, terminalID) = floating else {
            throw AgentError(
                code: "pane_not_found",
                message: "pane \(target.id) is not in herdr session \(target.session)",
            )
        }
        if onTop {
            page.floating[terminalID] = true
        }
        return AgentOutput(["pane": target.id, "floating": true, "onTop": page.floating[terminalID] == true,
                            "existing": existing])
    }

    static let unfloat = AgentCommand(
        name: "unfloat", usage: "unfloat <pane>", summary: "Puts a floating pane back in its tab",
    ) { call in
        let target = try call.target(call.argument("pane"))
        try call.done()
        guard let (page, terminalID) = target.floating else {
            throw AgentError(code: "not_floating", message: "pane \(target.id) does not float")
        }
        page.floating[terminalID] = nil
        return AgentOutput(["pane": target.id, "floating": false])
    }

    static let copy = AgentCommand(
        name: "copy", usage: "copy", summary: "Puts standard input on the Mac's clipboard",
        help: "At most 1 MiB of text. It never reads the clipboard.",
    ) { call in
        try call.done()
        let text = try await call.store.machine.exec().input(request: call.id)
        guard text.count <= AgentRequest.inputLimit else {
            throw AgentError(code: "bad_argument", message: "standard input is over 1 MiB")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: text, as: UTF8.self), forType: .string)
        return AgentOutput(["bytes": text.count], text: "")
    }
}

extension PaneTarget {
    /// The page whose window floats the pane, and its terminal.
    var floating: (Page, String)? {
        for page in WindowPages.windows.flatMap(\.withFloats)
            where page.store.session == session && page.store.machine.id == machine.id
        {
            if let terminalID = page.store.pane(id)?.terminalID, page.floating[terminalID] != nil {
                return (page, terminalID)
            }
        }
        return nil
    }
}
