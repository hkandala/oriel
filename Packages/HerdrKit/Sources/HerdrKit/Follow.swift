import Foundation

/// Where a followed file was read up to, so a new run goes on from there
/// (ui/chat-view#where-messages-come-from).
public struct FileMark: Equatable, Sendable {
    public var inode = ""
    /// Bytes read, whole lines only.
    public var offset = 0

    public init() {}
}

/// One line of a followed file, and the mark after it.
public enum FollowedLine: Sendable {
    /// The file is read from `mark` on: a new file (another inode, or shorter than the old mark) starts again, from its
    /// start. The lines before it belong to another file when `restarted`.
    case opened(FileMark, restarted: Bool)
    case line(String, FileMark)
    /// Read up to the whole lines the file had when it was opened: the lines after it come as they are written.
    case loaded
}

public extension Exec {
    /// Follows a file on the machine (a relative path is under the home folder) as `tail -F` does, from `mark` on,
    /// also before the file exists, until the stream is dropped. A file rotated meanwhile starts again at the next
    /// follow, which compares its inode with the mark's. `skip`: an awk pattern of the lines no parser reads (`0`:
    /// none),
    /// dropped on the machine so they never cross a remote machine's relay.
    func follow(_ path: String, from mark: FileMark, skip: String = "0") async throws -> AsyncStream<FollowedLine> {
        let lines = try await lines(Self.followScript, [path, String(mark.offset), mark.inode, skip])
        let (stream, continuation) = AsyncStream<FollowedLine>.makeStream()
        let reader = Task {
            var mark = mark, end = Int.max
            for await line in lines {
                let parts = line.split(separator: " ")
                if line.hasPrefix("oriel-follow ") {
                    guard parts.count == 4, let offset = Int(parts[2]), let opened = Int(parts[3]) else { continue }
                    let restarted = parts[1] != mark.inode || offset != mark.offset
                    mark = FileMark()
                    mark.inode = String(parts[1])
                    mark.offset = offset
                    end = opened
                    continuation.yield(.opened(mark, restarted: restarted))
                } else if line.hasPrefix("oriel-skip "), parts.count == 2, let bytes = Int(parts[1]) {
                    mark.offset += bytes
                } else {
                    // Whole lines from a line start only, so the byte count holds (a cut inside a character would
                    // not).
                    mark.offset += line.utf8.count + 1
                    continuation.yield(.line(line, mark))
                }
                if mark.offset >= end {
                    end = .max
                    continuation.yield(.loaded)
                }
            }
            continuation.finish()
        }
        // Ends `lines`, and so the script.
        continuation.onTermination = { _ in reader.cancel() }
        return stream
    }

    /// Prints a file's whole text each time it changes, as one line (a JSON record the program rewrites), checked
    /// every 0.3 s; the first of `paths` (relative ones under the home folder) that exists, or an empty line when none
    /// does.
    func watch(_ paths: [String]) async throws -> AsyncStream<String> {
        try await lines(Self.watchScript, paths)
    }

    /// A long-running script's lines until the stream is dropped, which closes its stdin: the wrapper then ends it
    /// (neither the script nor `tail` reads stdin).
    internal func lines(_ script: String, _ arguments: [String]) async throws -> AsyncStream<String> {
        let channel = try await run(["sh", "-c", TerminalStream.observeWrapper, "sh", "sh", "-c", script, "sh"]
            + arguments)
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let reader = Task {
            for await line in channel.lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            reader.cancel()
            channel.closeInput()
        }
        return stream
    }

    /// Waits for the file, then tells its inode, where it reads from (the old mark when it is the same file and no
    /// shorter, else its start) and where its whole lines end (a last line still being written comes later). awk
    /// passes the lines on and tells the bytes of each skipped one, so the mark still counts the file's bytes. It
    /// reads a pipe that only `tail` writes to (a FIFO opened, then removed at once): the wrapper's kill ends `tail`,
    /// and awk ends on its EOF, also when the script is killed before `tail` starts.
    static var followScript: String {
        #"""
        f=$1; case $f in /*) ;; *) f=$HOME/$f ;; esac
        while [ ! -f "$f" ]; do sleep 0.5; done
        n=$(ls -i "$f" | awk '{print $1}'); s=$(wc -c <"$f" | tr -d ' '); o=$2
        [ "$n" = "$3" ] && [ "$s" -ge "$o" ] || o=0
        [ -z "$(tail -c 1 "$f")" ] || s=$((s - $(tail -n 1 "$f" | wc -c)))
        echo "oriel-follow $n $o $s"
        p=$(mktemp -u "${TMPDIR:-/tmp}/oriel-follow.XXXXXX") && mkfifo -m 600 "$p" && exec 5<>"$p" 6<"$p" &&
          rm -f "$p" || exit 1
        LC_ALL=C awk "$4"' { print "oriel-skip " length($0) + 1; fflush(); next } { print; fflush() }' <&6 5>&- 6<&- &
        exec tail -c +$((o + 1)) -F "$f" 2>/dev/null >&5 5>&- 6<&-
        """#
    }

    static var watchScript: String {
        #"""
        o=x
        while :; do
          n=; for f; do
            case $f in /*) ;; *) f=$HOME/$f ;; esac
            [ -f "$f" ] && n=$(tr -d '\n' <"$f") && break
          done
          [ "$n" != "$o" ] && printf '%s\n' "$n" && o=$n
          sleep 0.3
        done
        """#
    }
}
