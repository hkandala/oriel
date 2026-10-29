import Foundation

/// One file of a patch.
public struct DiffFile: Equatable, Sendable {
    /// From the repository's root; a deleted file's old path.
    public var path: String
    /// The path before a rename.
    public var oldPath: String?
    /// `M`, `A`, `D` or `R`.
    public var letter: Character = "M"
    /// git prints no lines for a binary file.
    public var binary = false
    public var hunks: [Hunk] = []

    public var added: Int {
        hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } }
    }

    public var removed: Int {
        hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } }
    }
}

public struct Hunk: Equatable, Sendable {
    /// The whole `@@ -1,3 +1,4 @@ context` line.
    public let header: String
    public var lines: [DiffLine] = []
}

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable {
        case context, added, removed

        /// From a line's first character; nil for `\ No newline at end of file`.
        init?(_ mark: Character?) {
            switch mark {
            case " ": self = .context
            case "+": self = .added
            case "-": self = .removed
            default: return nil
            }
        }
    }

    public let kind: Kind
    public let text: String
    /// The line's number in the old and in the new file; nil on the side it is not in.
    public let old: Int?
    public let new: Int?
    /// The changed words, as UTF-16 offsets into `text` (the unit of NSString and JavaScript).
    public var words: [Range<Int>] = []
}

public extension Git {
    /// The patch, with renames, of one commit against its first parent, or with `commit` nil of the uncommitted
    /// changes: staged, unstaged and untracked files against HEAD.
    static func diff(_ root: String, commit: String?, exec: any Exec) async throws -> [DiffFile] {
        // The user's config must not change the format: color, an external tool, other prefixes, quoted names.
        let git = ["git", "-c", "core.quotePath=false"]
        let flags = ["--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "-M"]
        if let commit {
            // A hash from a pane's label: never an option.
            guard !commit.isEmpty,
                  commit.allSatisfy(\.isHexDigit) else { throw HerdrError.failed("No commit \(commit)") }
            return try await DiffFile.parse(exec.checkedOutput(
                git + ["-C", root, "show"] + flags + ["-m", "--first-parent", "--format=", commit],
                timeout: .seconds(30),
            ))
        }
        let script = #"""
        cd "$1" && shift && git "$@" HEAD || exit
        git ls-files -z -o --exclude-standard | xargs -0 -r -n 1 git "$@" --no-index -- /dev/null
        exit 0
        """#
        return try await DiffFile.parse(exec.checkedOutput(
            ["sh", "-c", script, "sh", root] + git.dropFirst() + ["diff"] + flags,
            timeout: .seconds(30),
        ))
    }
}

extension DiffFile {
    static func parse(_ patch: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var old = 0, new = 0
        for line in patch.split(separator: "\n") {
            if line.hasPrefix("diff --git ") {
                files.append(DiffFile(path: headerPath(line.dropFirst(11))))
            } else if files.isEmpty {
                continue
            } else if line.hasPrefix("@@ ") {
                let numbers = line.split(separator: " ").dropFirst().prefix(2)
                    .map { Int($0.dropFirst().prefix { $0 != "," }) ?? 0 }
                guard numbers.count == 2 else { continue }
                (old, new) = (numbers[0], numbers[1])
                files[files.count - 1].hunks.append(Hunk(header: String(line)))
            } else if files[files.count - 1].hunks.isEmpty {
                files[files.count - 1].header(line)
            } else if let kind = DiffLine.Kind(line.first) {
                let text = String(line.dropFirst())
                files[files.count - 1].hunks[files[files.count - 1].hunks.count - 1].lines.append(DiffLine(
                    kind: kind, text: text, old: kind == .added ? nil : old, new: kind == .removed ? nil : new,
                ))
                old += kind == .added ? 0 : 1
                new += kind == .removed ? 0 : 1
            }
        }
        for file in files.indices {
            for hunk in files[file].hunks.indices {
                markWords(&files[file].hunks[hunk].lines)
            }
        }
        return files
    }

    /// A line between `diff --git` and the first hunk.
    private mutating func header(_ line: Substring) {
        if line.hasPrefix("new file mode") {
            letter = "A"
        } else if line.hasPrefix("deleted file mode") {
            letter = "D"
        } else if line.hasPrefix("rename from ") {
            letter = "R"
            oldPath = Self.name(line.dropFirst(12))
        } else if line.hasPrefix("rename to ") {
            path = Self.name(line.dropFirst(10))
        } else if line.hasPrefix("+++ "), line != "+++ /dev/null" {
            path = String(Self.name(line.dropFirst(4)).dropFirst(2))
        } else if line.hasPrefix("Binary files ") {
            binary = true
        }
    }

    /// The path in `a/P b/P`. Only a rename's two paths differ, and its `rename` lines give them.
    private static func headerPath(_ paths: Substring) -> String {
        String(name(paths.hasPrefix("\"") ? paths : paths.prefix((paths.count - 1) / 2)).dropFirst(2))
    }

    /// A path as git prints it: in C quotes when it holds a quote, a backslash or a control character, and with a
    /// tab after it on `---` and `+++` lines when it holds a space.
    private static func name(_ text: Substring) -> String {
        guard text.hasPrefix("\"") else { return String(text.hasSuffix("\t") ? text.dropLast() : text) }
        var bytes: [UInt8] = []
        var rest = text.utf8.dropFirst()
        while let byte = rest.popFirst(), byte != UInt8(ascii: "\"") {
            guard byte == UInt8(ascii: "\\"), let next = rest.popFirst() else {
                bytes.append(byte)
                continue
            }
            if (UInt8(ascii: "0") ... UInt8(ascii: "7")).contains(next) {
                bytes.append(UInt8(String(decoding: [next] + rest.prefix(2), as: UTF8.self), radix: 8) ?? 0)
                rest = rest.dropFirst(2)
            } else {
                let escapes: [UInt8: UInt8] = [0x61: 7, 0x62: 8, 0x74: 9, 0x6E: 10, 0x76: 11, 0x66: 12, 0x72: 13]
                bytes.append(escapes[next] ?? next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Marks the changed words of each removed line against the added line at the same place in the block after it.
    static func markWords(_ lines: inout [DiffLine]) {
        var start = 0
        while start < lines.count {
            guard lines[start].kind == .removed else {
                start += 1
                continue
            }
            let removed = start ..< (lines[start...].firstIndex { $0.kind != .removed } ?? lines.count)
            let added = removed.upperBound ..< (lines[removed.upperBound...].firstIndex { $0.kind != .added }
                ?? lines.count)
            for (old, new) in zip(removed, added) {
                (lines[old].words, lines[new].words) = words(lines[old].text, lines[new].text)
            }
            start = added.upperBound
        }
    }

    private struct Token {
        var text: Substring
        var range: Range<Int>
        let isWord: Bool
    }

    /// The changed words of the old and the new line, or none when the two have nothing in common.
    /// ponytail: the difference costs O(n·d), so lines over 1,000 characters get no marks.
    static func words(_ old: String, _ new: String) -> ([Range<Int>], [Range<Int>]) {
        guard old.utf16.count <= 1000, new.utf16.count <= 1000 else { return ([], []) }
        let before = tokens(old), after = tokens(new)
        let difference = after.map(\.text).difference(from: before.map(\.text))
        guard difference.removals.count < before.count || difference.insertions.count < after.count else {
            return ([], [])
        }
        var removed: [Int] = [], inserted: [Int] = []
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.append(offset)
            case let .insert(offset, _, _): inserted.append(offset)
            }
        }
        return (marks(before, removed), marks(after, inserted))
    }

    /// Runs of letters, digits and `_` are one token; any other character is a token of its own.
    private static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        for index in text.indices {
            let character = text[index]
            let width = character.utf16.count
            let isWord = character.isLetter || character.isNumber || character == "_"
            if isWord, let last = tokens.last, last.isWord {
                tokens[tokens.count - 1].text = text[last.text.startIndex ... index]
                tokens[tokens.count - 1].range = last.range.lowerBound ..< offset + width
            } else {
                tokens.append(Token(text: text[index ... index], range: offset ..< offset + width, isWord: isWord))
            }
            offset += width
        }
        return tokens
    }

    /// The tokens' ranges, neighbors joined.
    private static func marks(_ tokens: [Token], _ changed: [Int]) -> [Range<Int>] {
        var marks: [Range<Int>] = []
        for range in changed.sorted().map({ tokens[$0].range }) {
            if let last = marks.last, last.upperBound == range.lowerBound {
                marks[marks.count - 1] = last.lowerBound ..< range.upperBound
            } else {
                marks.append(range)
            }
        }
        return marks
    }
}
