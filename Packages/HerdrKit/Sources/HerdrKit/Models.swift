import Foundation

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
    /// Only once a `worktree.*` call has looked at the workspace; a plain `workspace.create` leaves it out.
    public let worktree: Worktree?

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id", label, activeTabID = "active_tab_id", worktree
    }
}

/// A workspace's git checkout, as herdr tracks it.
public struct Worktree: Decodable, Equatable, Sendable {
    /// The repository's shared `.git` directory: the same for a repository and its linked worktrees.
    public let repoKey: String
    public let checkoutPath: String
    public let isLinkedWorktree: Bool

    enum CodingKeys: String, CodingKey {
        case repoKey = "repo_key", checkoutPath = "checkout_path", isLinkedWorktree = "is_linked_worktree"
    }
}

public struct Tab: Decodable, Sendable, Identifiable {
    public let id: String
    public let workspaceID: String
    public let label: String

    /// A tab the app draws before herdr has it (phase 25: a new tab shows at once).
    public init(id: String, workspaceID: String, label: String) {
        self.id = id
        self.workspaceID = workspaceID
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id = "tab_id", workspaceID = "workspace_id", label
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
    /// herdr's viewport, which every client of the pane shares.
    public let scroll: PaneScroll?

    enum CodingKeys: String, CodingKey {
        case id = "pane_id", terminalID = "terminal_id", tabID = "tab_id", label, cwd, agent
        case title = "terminal_title_stripped", scroll
    }
}

public struct PaneScroll: Decodable, Sendable {
    /// Lines from the bottom; 0 is the bottom.
    public let offsetFromBottom: Int?
    /// The scrollback above the screen.
    public let maxOffsetFromBottom: Int?
    public let viewportRows: Int?

    enum CodingKeys: String, CodingKey {
        case offsetFromBottom = "offset_from_bottom", maxOffsetFromBottom = "max_offset_from_bottom"
        case viewportRows = "viewport_rows"
    }
}

/// A float request on a pane (talking-to-herdr#float-requests): its token `oriel-float` names the pane to float as
/// `‹session›/‹pane id›`, `oriel-float-id` is a nonce.
public struct FloatRequest: Sendable {
    public let session: String
    public let pane: String
    public let nonce: String

    init?(_ tokens: [String: String]?) {
        let parts = tokens?["oriel-float"]?.split(separator: "/", maxSplits: 1).map(String.init) ?? []
        guard parts.count == 2, let nonce = tokens?["oriel-float-id"] else { return nil }
        session = parts[0]
        pane = parts[1]
        self.nonce = nonce
    }
}

/// An agent pane. Only the pane id is required, so one odd entry cannot fail the snapshot.
public struct Agent: Decodable, Sendable {
    public let paneID: String
    public let terminalID: String?
    /// herdr's agent kind (`codex`).
    public let agent: String?
    /// A label set through `pane.report_metadata`; wins over `agent` as the name.
    public let displayAgent: String?
    public let status: AgentStatus
    /// The number of the agent's last finish (working or blocked to idle); null again at its next status change.
    public let completionSeq: Int?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id", terminalID = "terminal_id", agent, displayAgent = "display_agent"
        case status = "agent_status", completionSeq = "completion_seq"
    }
}

/// In an extension, so tests keep the memberwise init.
public extension Agent {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneID = try container.decode(String.self, forKey: .paneID)
        terminalID = try? container.decode(String.self, forKey: .terminalID)
        agent = try? container.decode(String.self, forKey: .agent)
        displayAgent = try? container.decode(String.self, forKey: .displayAgent)
        status = (try? container.decode(AgentStatus.self, forKey: .status)) ?? .unknown
        completionSeq = try? container.decode(Int.self, forKey: .completionSeq)
    }
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
    /// `pane.split`'s new pane.
    let pane: Pane?
}

/// `pane.move`: the pane where it went (a move to another workspace gives it a new id).
struct Moved: Decodable {
    let moveResult: Change

    enum CodingKeys: String, CodingKey { case moveResult = "move_result" }
}

/// `pane.swap`.
struct Swapped: Decodable {
    let swap: Change
}

/// A move or a swap: `changed:false` with herdr's reason when it refused.
struct Change: Decodable {
    let changed: Bool?
    let reason: String?
    let pane: Pane?

    func check() throws {
        if changed == false {
            throw HerdrError.refused(reason ?? "unknown")
        }
    }
}

/// `pane.read`.
struct Read: Decodable {
    struct Text: Decodable {
        let text: String
    }

    let read: Text
}

/// `pane.process_info`: the pane's shell and its foreground processes.
struct ProcessInfoResult: Decodable {
    let processInfo: PaneProcesses

    enum CodingKeys: String, CodingKey { case processInfo = "process_info" }
}

/// What runs in a pane's foreground, as the icon matcher and the card header need it.
public struct Program: Equatable, Sendable {
    public let name: String
    public let argv0: String?
    /// The first argument that is not an option: the script a `node` or `bun` runs (`pi`'s cli.js).
    /// ponytail: `node --require x.js cli.js` or `bun run dev` pick the wrong one (the header and the base-name
    /// match); skip option values if it matters.
    public let script: String?
    /// Only the pane's shell runs.
    public let isShell: Bool

    public init(name: String, argv0: String? = nil, script: String? = nil, isShell: Bool = false) {
        self.name = name
        self.argv0 = argv0
        self.script = script
        self.isShell = isShell
    }

    /// The name people know it by: a Node CLI's script name (`gemini`), else the process name.
    public var title: String {
        guard let script, ["node", "bun"].contains(name) else { return name }
        return URL(filePath: script).lastPathComponent
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

    /// What runs in the foreground besides the shell, else the shell itself (`isShell`, design D41); nil when
    /// herdr lists nothing. A program the shell `exec`ed has the shell's pid, so the shell's pid counts only while
    /// it is still a shell.
    var program: Program? {
        let program = foregroundProcesses.first { $0.pid != shellPID || !$0.isShell }
        return (program ?? foregroundProcesses.first).map { process in
            Program(name: process.name, argv0: process.argv0,
                    script: process.argv?.dropFirst().first { !$0.hasPrefix("-") }, isShell: program == nil)
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
