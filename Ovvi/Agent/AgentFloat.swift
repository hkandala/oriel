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
            throw AgentError.noWindow(call.store.session)
        }
        let existing = target.floating != nil
        WindowPages.float(session: target.session, pane: target.id, machine: machine.id, over: window, agent: true)
        // A session with no page opens a float-only one, which floats the pane once it connects.
        try await settle(for: .seconds(8)) { target.floating != nil || window.floatPending == nil }
        let floating = target.floating
        if floating == nil, case let .failed(error) = target.store?.state {
            throw error
        }
        guard let (page, terminalID) = floating else {
            throw AgentError.paneNotFound(target.id, in: target.session)
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

    static let balance = AgentCommand(
        name: "balance", usage: "balance [<pane>]",
        summary: "Evens out the splits of a pane's tab, this pane's by default",
        help: "As Balance Splits: each run of side-by-side or stacked panes gets equal shares.",
    ) { call in
        let target = try call.optionalArgument().map(call.target) ?? call.asking
        try call.done()
        let (store, pane) = try call.found(target)
        // Its tab once the writes before it are done: they can move the pane.
        let tab = try await store.request { client in
            let tab = store.pane(pane.id)?.tabID ?? pane.tabID
            try await store.balance(tab, client)
            return tab
        }
        return AgentOutput(["pane": target.id, "tab": tab])
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
