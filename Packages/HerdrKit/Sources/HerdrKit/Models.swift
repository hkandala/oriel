// Lenient models of herdr's JSON: only the fields the app uses. Unknown fields are ignored and
// unknown enum values fall back, so a newer herdr does not break decoding.

public struct Snapshot: Decodable, Sendable {
    /// herdr's version: the snapshot read is also the version check.
    let version: String?
    public let focusedWorkspaceID: String?
    public let workspaces: [Workspace]
    public let tabs: [Tab]
    public let panes: [Pane]
    public let agents: [Agent]
    let layouts: [Layout]
    /// Each tab's split tree by tab id. Filled by `HerdrClient.snapshot()`.
    public internal(set) var trees: [String: SplitNode] = [:]
    /// Each tab's focused pane; herdr's global `focused` marks only one pane of all tabs.
    public var focusedPaneIDs: Set<String> {
        Set(layouts.compactMap(\.focusedPaneID))
    }

    enum CodingKeys: String, CodingKey {
        case focusedWorkspaceID = "focused_workspace_id"
        case version, workspaces, tabs, panes, agents, layouts
    }
}

public struct Workspace: Decodable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let activeTabID: String
    public let agentStatus: AgentStatus

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id", label, activeTabID = "active_tab_id", agentStatus = "agent_status"
    }
}

public struct Tab: Decodable, Sendable, Identifiable {
    public let id: String
    public let workspaceID: String
    public let label: String
    public let agentStatus: AgentStatus

    enum CodingKeys: String, CodingKey {
        case id = "tab_id", workspaceID = "workspace_id", label, agentStatus = "agent_status"
    }
}

public struct Pane: Decodable, Sendable, Identifiable {
    public let id: String
    /// Optional so one odd pane cannot fail the whole snapshot.
    public let terminalID: String?
    public let tabID: String
    public let label: String?
    public let cwd: String?
    /// herdr's agent kind (`claude`), detected or reported.
    public let agent: String?
    /// The terminal title without the status glyphs herdr strips (`✳`, spinners).
    public let title: String?

    enum CodingKeys: String, CodingKey {
        case id = "pane_id", terminalID = "terminal_id", tabID = "tab_id", label, cwd, agent
        case title = "terminal_title_stripped"
    }
}

/// Only the pane: the events stream asks for status changes of agent panes.
public struct Agent: Decodable, Sendable {
    public let paneID: String

    enum CodingKeys: String, CodingKey { case paneID = "pane_id" }
}

public enum AgentStatus: String, Decodable, Sendable {
    case idle, working, blocked, done, unknown

    public init(from decoder: any Decoder) throws {
        self = try Self(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// What `workspace.create` and `tab.create` return: the new tab, to select once a snapshot shows it. Any other
/// reply decodes as one too (its tab is optional).
struct Created: Decodable {
    let tab: Tab?
}

/// `pane.process_info`: the pane's shell and its foreground processes.
struct ProcessInfoResult: Decodable {
    let processInfo: PaneProcesses

    enum CodingKeys: String, CodingKey { case processInfo = "process_info" }
}

/// The program a pane runs besides its shell, as the icon matcher needs it.
public struct Program: Equatable, Sendable {
    public let name: String
    public let argv0: String?
    /// The first argument that is not an option: the script a `node` or `bun` runs (`pi`'s cli.js).
    public let script: String?

    public init(name: String, argv0: String? = nil, script: String? = nil) {
        self.name = name
        self.argv0 = argv0
        self.script = script
    }
}

struct PaneProcesses: Decodable {
    struct Process: Decodable {
        let pid: Int
        let name: String
        let argv0: String?
        let argv: [String]?

        /// A login shell (`-zsh`) or a known shell by name.
        var isShell: Bool {
            argv0?.hasPrefix("-") == true || ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu"]
                .contains(name)
        }
    }

    let shellPID: Int
    let foregroundProcesses: [Process]

    /// What runs in the foreground besides the shell; nil when nothing does (design D41). A program the shell
    /// `exec`ed has the shell's pid, so the shell's pid counts only while it is still a shell.
    var program: Program? {
        foregroundProcesses.first { $0.pid != shellPID || !$0.isShell }.map { process in
            Program(name: process.name, argv0: process.argv0,
                    script: process.argv?.dropFirst().first { !$0.hasPrefix("-") })
        }
    }

    enum CodingKeys: String, CodingKey { case shellPID = "shell_pid", foregroundProcesses = "foreground_processes" }
}

public struct Session: Decodable, Equatable, Sendable {
    public let name: String
    public let running: Bool

    /// herdr's rule for session names: ASCII letters, digits, `.`, `_` and `-`, at most 64 bytes, not `.` or `..`.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 64 && name != "." && name != ".."
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}

struct Layout: Decodable {
    let tabID: String
    let focusedPaneID: String?
    let panes: [Pane]
    let splits: [Split]

    struct Pane: Decodable {
        let pane_id: String // swiftlint:disable:this identifier_name
    }

    struct Split: Decodable {
        let id: String
        let direction: SplitNode.Direction
        let ratio: Double
    }

    enum CodingKeys: String, CodingKey { case tabID = "tab_id", focusedPaneID = "focused_pane_id", panes, splits }
}
