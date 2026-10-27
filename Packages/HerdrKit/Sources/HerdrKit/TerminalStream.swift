import Foundation

/// One `herdr terminal session control|observe` run: herdr's rendering of a pane comes out as
/// frames, commands go in as NDJSON. Only `control` takes commands; `observe` only watches.
public struct TerminalStream: Sendable {
    public enum Event: Sendable, Equatable {
        case frame(Frame)
        /// The last event: the stream is over.
        case closed(Closed)
    }

    public struct Frame: Sendable, Equatable {
        /// The real PTY size on a `control` stream.
        public let width: Int
        public let height: Int
        /// ANSI bytes, herdr's own rendering of the visible screen (no input modes).
        public let bytes: Data
    }

    /// Why a stream ended, from herdr's reason text (design: how a stream ends).
    public enum Closed: Sendable, Equatable {
        /// Another client controls the pane, or took it with `--takeover`.
        case held
        /// We closed it, or the terminal is not found or has exited.
        case ended
        /// herdr is replacing itself; open again after a moment.
        case liveUpdate
        /// Anything else, with herdr's text: a failed handshake, a stopped server.
        case failed(String)

        init(reason: String) {
            self = if reason.contains("already has an attached client") || reason.contains("taken over") {
                .held
            } else if reason.contains("not found") || reason.contains("exited") || reason.contains("detached") {
                .ended
            } else if reason.contains("live update") {
                .liveUpdate
            } else {
                .failed(reason)
            }
        }
    }

    public enum MouseAction: String, Sendable { case down, up, drag } // swiftlint:disable:this identifier_name
    public enum MouseButton: String, Sendable { case left, middle, right }

    /// Frames until one `.closed`, then the end. Dropping the iteration ends the run.
    public let events: AsyncStream<Event>
    let channel: Channel

    init(_ channel: Channel) {
        self.channel = channel
        events = AsyncStream { continuation in
            let reader = Task {
                for await line in channel.lines {
                    switch Self.event(line) {
                    case let .closed(reason)?:
                        continuation.yield(.closed(reason))
                        continuation.finish()
                        return
                    case let event?:
                        continuation.yield(event)
                    case nil:
                        break
                    }
                }
                // No `terminal.closed`: the CLI failed (exit 1, reason on stderr) or was killed.
                let (status, stderr) = await channel.exit()
                let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(.closed(.failed(text.isEmpty ? "herdr exited \(status)" : text)))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                reader.cancel()
                channel.terminate()
            }
        }
    }

    /// One stdout line as an event; nil for lines we do not know.
    static func event(_ line: String) -> Event? {
        struct Line: Decodable {
            let type: String
            let width: Int?, height: Int?
            let bytes: String?, reason: String?
        }
        guard let line = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)) else { return nil }
        switch line.type {
        case "terminal.frame":
            guard let width = line.width, let height = line.height,
                  let bytes = line.bytes.flatMap({ Data(base64Encoded: $0) })
            else { return nil }
            return .frame(Frame(width: width, height: height, bytes: bytes))
        case "terminal.closed":
            return .closed(Closed(reason: line.reason ?? ""))
        default:
            return nil
        }
    }

    // MARK: Commands (control only)

    /// Bytes for the PTY, unchanged. A whole bracketed paste (`ESC[200~…ESC[201~`) is re-framed by
    /// herdr for the app's own paste mode.
    public func input(_ text: String) {
        send(["type": "terminal.input", "text": text])
    }

    public func resize(cols: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        send(["type": "terminal.resize", "cols": cols, "rows": rows,
              "cell_width_px": cellWidth, "cell_height_px": cellHeight])
    }

    /// A wheel at a cell, up when `lines` is negative: herdr sends it to a mouse app or moves the
    /// pane's viewport.
    public func scroll(lines: Int, column: Int, row: Int, modifiers: Int) {
        send(["type": "terminal.scroll", "direction": lines < 0 ? "up" : "down", "lines": abs(lines),
              "column": column, "row": row, "modifiers": modifiers])
    }

    /// 0-based cells; modifiers are crossterm bits (1 shift, 2 ctrl, 4 alt). herdr encodes the event
    /// for the app's mouse mode and drops it when the app has none.
    public func mouse(_ action: MouseAction, _ button: MouseButton, column: Int, row: Int, modifiers: Int) {
        send(["type": "terminal.mouse", "action": action.rawValue, "button": button.rawValue,
              "column": column, "row": row, "modifiers": modifiers])
    }

    /// Lets go of the pane by closing stdin: herdr answers `detached` (input sent before still arrives) and the
    /// run ends (talking-to-herdr, Running commands).
    public func close() {
        channel.closeInput()
        // The one fallback: a run still going 1 s later (a hung herdr, a write stuck on a full pipe) is killed.
        Task {
            try? await Task.sleep(for: .seconds(1))
            channel.terminate()
        }
    }

    private func send(_ command: [String: any Sendable]) {
        // Only strings and numbers: serializing cannot fail.
        channel.write(jsonLine(command) ?? "")
    }
}

extension TerminalStream {
    /// observe ignores stdin's end, so this wrapper ends it then (talking-to-herdr, Running commands). The watcher lets
    /// go of stdout and stderr, so a run that exits by itself (a failed handshake) ends the stream with its status and
    /// reason; fd 3
    /// because a background job's stdin is /dev/null. The watcher goes too, so it never kills a reused pid.
    static let observeWrapper = #"exec 3<&0; "$@" & c=$!; { cat <&3 >/dev/null; kill $c; } >/dev/null 2>&1 & w=$!; "#
        + "wait $c 2>/dev/null; s=$?; kill $w 2>/dev/null; exit $s"
}

public extension HerdrClient {
    /// Opens a pane's terminal by its `terminal_id`, so the stream survives the pane moving.
    /// `--session` wins over `HERDR_SOCKET_PATH` and `HERDR_SESSION`.
    nonisolated func terminal(
        _ terminalID: String,
        cols: Int,
        rows: Int,
        observe: Bool = false,
        takeover: Bool = false,
    ) async throws -> TerminalStream {
        var argv = try await [herdr(), "--session", session, "terminal", "session", observe ? "observe" : "control",
                              terminalID, "--cols", "\(cols)", "--rows", "\(rows)"]
        if observe {
            argv = ["sh", "-c", TerminalStream.observeWrapper, "sh"] + argv
        } else if takeover {
            argv.append("--takeover")
        }
        return try await TerminalStream(exec.run(argv))
    }
}
