import Foundation

/// One entry of the program icon catalog (`resources/icons/catalog.json`): only the fields the app uses.
public struct ProgramIcon: Decodable, Sendable {
    public let id: String
    public let tile: Tile
    let match: Match

    public struct Tile: Decodable, Sendable {
        /// `#rrggbb`.
        public let background: String
        public let glyph: String
    }

    struct Match: Decodable {
        let agent: [String]?
        let process: [String]?
        let titlePrefix: [String]?
        let scriptSuffix: [String]?
    }
}

public extension [ProgramIcon] {
    /// The id of a pane's icon. The first hit wins: herdr's agent, the foreground process (name, argv0; a Node
    /// CLI's script first), the title; then `terminal` when only the shell runs, `placeholder` for a program or agent
    /// the catalog does not know.
    func iconID(agent: String?, program: Program?, title: String?) -> String {
        func find(_ hit: (ProgramIcon.Match) -> Bool) -> String? {
            first { hit($0.match) }?.id
        }
        if let agent, let id = find({ $0.agent?.contains(agent) == true }) {
            return id
        }
        if let program, !program.isShell {
            // A path's folder; a login shell's leading `-`.
            let base = { (path: String) in String(URL(filePath: path).lastPathComponent.trimmingPrefix("-")) }
            var names = [program.name, program.argv0].compactMap(\.self).map(base)
            // A Node CLI (`pi`) is its script, not `node`: the package's path, else the bin link's name it was
            // started through (`gemini`).
            if let script = program.script, names.contains(where: ["node", "bun"].contains) {
                if let id = find({ $0.scriptSuffix?.contains { script.hasSuffix($0) } == true }) {
                    return id
                }
                names.insert(base(script), at: 0)
            }
            for name in names {
                if let id = find({ $0.process?.contains(name) == true }) {
                    return id
                }
            }
        }
        if let title, let id = find({ $0.titlePrefix?.contains { title == $0 || title.hasPrefix($0 + " ") } == true }) {
            return id
        }
        return agent == nil && program?.isShell != false ? "terminal" : "placeholder"
    }
}
