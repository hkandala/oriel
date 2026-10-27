import Foundation

extension HerdrClient {
    /// The session's OSC 52 writes (talking-to-herdr, Clipboard). herdr gives a pane's clipboard write only to the
    /// shell client in front, its own TUI's kind, never to a terminal stream, so this run is such a client: a small
    /// Perl one, which prints each write's text as base64 on a line and ends when its stdin or herdr's socket does.
    func watchClipboard() async throws -> AsyncStream<String> {
        let channel = try await exec.run(["perl", "-e", Self.clipboardScript, herdr(), session])
        return AsyncStream { continuation in
            let reader = Task {
                for await line in channel.lines {
                    if let data = Data(base64Encoded: line) {
                        continuation.yield(String(decoding: data, as: UTF8.self))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                reader.cancel()
                channel.terminate()
            }
        }
    }

    /// herdr's client socket is its API socket's with `-client` (`src/server/socket_paths.rs`). The client speaks
    /// endpoint generation 1, which herdr keeps for every later version (`src/protocol/endpoint.rs`): frames are a u32
    /// little-endian length and a bincode message, whose first byte is its variant (20 `EndpointControl`, the hello;
    /// 5 `Clipboard {data}`, a base64 string after a varint length: one byte under 251, else 251 and a u16 or 252 and a
    /// u32). `surface_active` makes it the client in front, which is what gets the writes; it never sends input or
    /// focus. Alone, it lays out every pane no stream holds at its size: 120 × 40, herdr's size with no client.
    static let clipboardScript = #"""
    use strict; use warnings; use IO::Socket::UNIX; use IO::Select;
    my ($herdr, $session) = @ARGV;
    open(my $list, '-|', $herdr, '--session', $session, 'session', 'list', '--json') or die "$herdr: $!\n";
    my $json = do { local $/; <$list> };
    my ($entry) = $json =~ /(\{[^{}]*"name":"\Q$session\E"[^{}]*\})/ or die "no session $session\n";
    my ($api) = $entry =~ /"socket_path":"([^"]+)\.sock"/ or die "no socket for $session\n";
    my $socket = IO::Socket::UNIX->new(Peer => "$api-client.sock") or die "$api-client.sock: $!\n";
    sub string { my $n = length $_[0]; ($n < 251 ? pack('C', $n) : pack('Cv', 251, $n)) . $_[0] }
    my $hello = pack('C', 20) . string('endpoint.hello.v1') . string('{"generation":1,"cell_width_px":0,'
        . '"cell_height_px":0,"surface_size":{"cols":120,"rows":40},"pixel_mouse":false,"direct_graphics":false,'
        . '"endpoint_keybindings":false,"mouse_capture":false,"surface_active":true,'
        . '"snapshot_codecs":["shell.snapshot.v1"],"surface_codecs":["shell.surface.v1"],'
        . '"input_codecs":["shell.input.semantic.v1"],"blob_codecs":["shell.blob.v1"]}');
    syswrite($socket, pack('V', length $hello) . $hello) or die "herdr: $!\n";
    $| = 1;
    my $select = IO::Select->new(\*STDIN, $socket);
    my $frames = '';
    while (1) {
        for my $fh ($select->can_read) {
            exit 0 unless sysread($fh, my $chunk, 65536);
            next if fileno $fh == 0;
            $frames .= $chunk;
            while (length $frames >= 4 && length $frames >= 4 + (my $n = unpack('V', $frames))) {
                my $message = substr($frames, 4, $n);
                substr($frames, 0, 4 + $n) = '';
                next unless ord $message == 5;
                my ($size, $at) = (ord substr($message, 1, 1), 2);
                ($size, $at) = (unpack('v', substr($message, 2, 2)), 4) if $size == 251;
                ($size, $at) = (unpack('V', substr($message, 2, 4)), 6) if $size == 252;
                print substr($message, $at, $size), "\n";
            }
        }
    }
    """#
}
