import Foundation
import HerdrKit
import Testing

/// The repository's root.
private let root = URL(filePath: #filePath).appending(path: "../../../../..").standardized

/// The app's catalog, read from the repository.
private let catalog: [ProgramIcon] = {
    let url = root.appending(path: "resources/icons/catalog.json")
    return (try? JSONDecoder().decode([ProgramIcon].self, from: Data(contentsOf: url))) ?? []
}()

private func icon(agent: String? = nil, _ program: Program? = nil, title: String? = nil) -> String {
    catalog.iconID(agent: agent, program: program, title: title)
}

/// The app draws nothing for a missing image set and the neutral tile for a bad color, silently.
@Test func `every icon has its image set and two tile colors`() throws {
    #expect(catalog.count > 100)
    let hex = /#[0-9a-f]{6}/
    for icon in catalog {
        let set = root.appending(path: "Oriel/Assets.xcassets/program.\(icon.id).imageset/\(icon.id).svg")
        #expect(FileManager.default.fileExists(atPath: set.path), "\(icon.id)")
        #expect(try hex.wholeMatch(in: icon.tile.background) != nil && hex.wholeMatch(in: icon.tile.glyph) != nil)
    }
}

@Test func `herdr's agent wins`() {
    #expect(icon(agent: "claude", Program(name: "node"), title: "π - x") == "claude")
    // An agent the catalog does not know falls through to the process.
    #expect(icon(agent: "someday", Program(name: "vim")) == "vim")
}

@Test func `the process matches by name, argv0, a Node CLI's script first`() {
    #expect(icon(Program(name: "vim")) == "vim")
    #expect(icon(Program(name: "nvim-wrapper", argv0: "/opt/homebrew/bin/nvim")) == "neovim")
    // A login shell's dash; a nested shell is a program of its own.
    #expect(icon(Program(name: "-bash")) == "bash")
    // A Node CLI run through its bin link: the link's name.
    #expect(icon(Program(name: "node", argv0: "node", script: "/opt/homebrew/bin/gemini")) == "gemini")
    // Through the package's own path: its suffix (the name, node, would say Node.js otherwise).
    let piCLI = Program(name: "node", argv0: "node", script: "/x/node_modules/@earendil/pi-coding-agent/dist/cli.js")
    #expect(icon(piCLI) == "pi")
    #expect(icon(Program(name: "node", argv0: "node", script: "server.js")) == "node")
    // Only a runtime's script counts: vim editing a file named git is vim.
    #expect(icon(Program(name: "vim", script: "git")) == "vim")
}

@Test func `the title's first word matches when nothing else does`() {
    #expect(icon(title: "π - oriel") == "pi")
    #expect(icon(title: "Claude Code") == "claude")
    #expect(icon(title: "πr squared") == "terminal")
}

@Test func `a shell is the terminal, an unknown program or agent the placeholder`() {
    #expect(icon() == "terminal")
    #expect(icon(Program(name: "zsh", isShell: true), title: "π - x") == "pi")
    #expect(icon(Program(name: "fish", isShell: true)) == "terminal")
    #expect(icon(agent: "someday") == "placeholder")
    #expect(icon(title: "~/code") == "terminal")
    #expect(icon(Program(name: "frobnicate")) == "placeholder")
}
