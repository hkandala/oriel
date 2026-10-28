import Foundation

/// Where a followed file was read up to, so a new run goes on from there
/// (future-work/chat-view#where-messages-come-from).
public struct FileMark: Equatable, Sendable {
    public var inode = ""
    /// Bytes read, whole lines only.
    public var offset = 0

    public init() {}
}

/// One line of a followed file, and the mark after it.
public enum FollowedLine: Sendable {
    /// The file is read from `mark` on: a new file (another inode, or shorter than the old mark) starts again, from
    /// its last 256 KiB. The lines before it belong to another file when `restarted`.
    case opened(FileMark, restarted: Bool)
    case line(String, FileMark)
}

public extension Exec {
    /// Follows a file on the machine as `tail -F` does, from `mark` on (also before the file exists, and across
    /// rotation), until the stream is dropped. A file read from its last 256 KiB drops its first, partial line.
    func follow(_ path: String, from mark: FileMark) async throws -> AsyncStream<FollowedLine> {
        let channel = try await run(Self.ending(Self.followScript, [path, String(mark.offset), mark.inode]))
        let (stream, continuation) = AsyncStream<FollowedLine>.makeStream()
        let reader = Task {
            var mark = mark, partial = false
            for await line in channel.lines {
                if line.hasPrefix("oriel-follow ") {
                    let parts = line.split(separator: " ")
                    guard parts.count == 4, let offset = Int(parts[2]) else { continue }
                    let restarted = parts[1] != mark.inode || offset != mark.offset
                    mark = FileMark()
                    mark.inode = String(parts[1])
                    mark.offset = offset
                    partial = restarted && offset > 0 && parts[3] == "cut"
                    continuation.yield(.opened(mark, restarted: restarted))
                    continue
                }
                mark.offset += line.utf8.count + 1
                if partial {
                    partial = false
                } else {
                    continuation.yield(.line(line, mark))
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            reader.cancel()
            channel.closeInput()
        }
        return stream
    }

    /// Prints a file's whole text each time it changes, as one line (a JSON record the program rewrites), checked
    /// every 0.3 s; the first of `paths` (relative ones under the home folder) that exists, or an empty line when none
    /// does.
    func watch(_ paths: [String]) async throws -> AsyncStream<String> {
        let channel = try await run(Self.ending(Self.watchScript, paths))
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

    /// The script, ended when its stdin closes (the app dropped the stream, or quit): neither it nor `tail` reads
    /// stdin.
    private static func ending(_ script: String, _ arguments: [String]) -> [String] {
        ["sh", "-c", TerminalStream.observeWrapper, "sh", "sh", "-c", script, "sh"] + arguments
    }

    /// Waits for the file, then tells its inode and where it reads from: the old mark when it is the same file and no
    /// shorter, else the last 256 KiB ("cut" when that is not the start).
    static var followScript: String {
        #"""
        while [ ! -f "$1" ]; do sleep 0.5; done
        n=$(ls -i "$1" | awk '{print $1}'); s=$(wc -c <"$1" | tr -d ' '); o=$2; c=whole
        if [ "$n" != "$3" ] || [ "$s" -lt "$o" ]; then
          o=0; [ "$s" -gt 262144 ] && o=$((s - 262144)) && c=cut
        fi
        echo "oriel-follow $n $o $c"
        exec tail -c +$((o + 1)) -F "$1" 2>/dev/null
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
          [ "$n" != "$o" ] && echo "$n" && o=$n
          sleep 0.3
        done
        """#
    }
}
