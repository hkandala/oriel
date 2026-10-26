#if os(macOS)
    import Foundation
    import Synchronization

    /// One remote process that carries every run of a host over one SSH session (phase 26, round 2): a server may
    /// allow only a few sessions per connection (`MaxSessions`), and a second connection would ask for a second
    /// passcode. Runs are lines both ways, as herdr's bridge, events and terminal streams are. The app sends
    /// `o <id> <command hex>` (open), `w <id> <line>`, `c <id>` (close stdin) and `k <id>` (SIGKILL by pid, then close
    /// stdin); the relay answers `l <id> <line>` and, once the run's output ended and it was reaped,
    /// `x <id> <status> <stderr hex>`.
    /// ponytail: Perl, which nearly every Unix has (Debian's perl-base is essential); a machine without it shows
    /// "Oriel needs Perl". A relay in another language when one is missed.
    final class Relay: Sendable {
        private struct Run {
            let lines: AsyncStream<String>.Continuation
            let exit: AsyncStream<(Int32, String)>.Continuation
        }

        private struct State {
            var next = 0
            var open: [Int: Run] = [:]
            var alive = true
        }

        private let channel: Channel
        private let state = Mutex(State())

        var alive: Bool {
            state.withLock { $0.alive }
        }

        private init(_ channel: Channel) {
            self.channel = channel
        }

        /// The relay on this channel (an SSH session that runs `perl -e script`); nil when it does not greet within
        /// 10 s (no Perl there).
        static func start(_ channel: Channel) async -> Relay? {
            let relay = Relay(channel)
            let (greeted, greeting) = AsyncStream<Bool>.makeStream()
            Task { await relay.route(greeting) }
            let ready = try? await withTimeout(.seconds(10), onTimeout: channel.terminate) {
                await greeted.first { _ in true } ?? false
            }
            return ready == true ? relay : nil
        }

        /// Every line of the relay to its run; when the session ends, every run ends with it.
        private func route(_ greeting: AsyncStream<Bool>.Continuation) async {
            for await line in channel.lines {
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3, let id = Int(parts[1]) else {
                    if line == "oriel-relay 1" {
                        greeting.yield(true)
                    }
                    continue
                }
                if parts[0] == "l" {
                    _ = state.withLock { $0.open[id] }?.lines.yield(String(parts[2]))
                } else if parts[0] == "x", let run = state.withLock({ $0.open.removeValue(forKey: id) }) {
                    let result = parts[2].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                    let stderr = result.count == 2 ? Self.unhex(result[1]) : ""
                    run.lines.finish()
                    run.exit.yield((Int32(result[0]) ?? -1, stderr))
                    run.exit.finish()
                }
            }
            let open = state.withLock { state in
                state.alive = false
                defer { state.open = [:] }
                return state.open.values
            }
            for run in open {
                run.lines.finish()
                run.exit.yield((255, "The SSH connection closed"))
                run.exit.finish()
            }
            greeting.yield(false)
        }

        /// One run of the command (POSIX `sh`) on the machine, as a channel of its own.
        func run(_ command: String) throws -> Channel {
            let (lines, linesContinuation) = AsyncStream<String>.makeStream()
            let (exits, exitContinuation) = AsyncStream<(Int32, String)>.makeStream()
            let id = state.withLock { state -> Int? in
                guard state.alive else { return nil }
                state.next += 1
                state.open[state.next] = Run(lines: linesContinuation, exit: exitContinuation)
                return state.next
            }
            guard let id else { throw HerdrError.failed("The SSH connection closed") }
            channel.write("o \(id) \(Data(command.utf8).map { String(format: "%02x", $0) }.joined())")
            let exit = Task { await exits.first { _ in true } ?? (-1, "") }
            let channel = channel
            // A dropped stream kills the run; one that ended at its end leaves the exit to come.
            linesContinuation.onTermination = { reason in
                if case .cancelled = reason {
                    channel.write("k \(id)")
                }
            }
            return Channel(
                lines: lines,
                write: { channel.write("w \(id) \($0)") },
                closeInput: { channel.write("c \(id)") },
                terminate: {
                    channel.write("k \(id)")
                    linesContinuation.finish()
                },
                exit: { await exit.value },
            )
        }

        private static func unhex(_ hex: Substring) -> String {
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while let end = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
                bytes.append(UInt8(hex[index ..< end], radix: 16) ?? 0)
                index = end
            }
            return String(decoding: bytes, as: UTF8.self)
        }

        /// The relay: `select` over its stdin and every run's stdout and stderr; a run's lines go out whole, so frames
        /// of two runs never mix; writes to a run's stdin wait in its own buffer, so a run that reads nothing never
        /// holds up the others. When its stdin ends (the app quit, the connection dropped) it exits, and every run's
        /// stdin closes with it.
        static let script = #"""
        use strict; use warnings; use IO::Handle; use IO::Select; use POSIX (); use Fcntl;
        $SIG{PIPE} = 'IGNORE';
        $| = 1;
        my $select = IO::Select->new(\*STDIN);
        my (%input, %pending, %closing, %pid, %err, %open, %owner);
        my $commands = '';
        sub put { print @_ or exit 1 }
        # Runs whose output ended: reaped when they exit; how many still run.
        sub reap {
            my $left = 0;
            for my $id (grep { !$open{$_} } keys %pid) {
                if (waitpid($pid{$id}, POSIX::WNOHANG()) > 0) {
                    my $status = $? & 127 ? $? & 127 : $? >> 8;
                    put("x $id $status " . unpack('H*', $err{$id}) . "\n");
                    delete $_->{$id} for \%pid, \%err, \%open;
                } else {
                    $left++;
                }
            }
            return $left;
        }
        sub close_input {
            my $id = shift;
            close(delete $input{$id}) if $input{$id};
            delete $pending{$id}; delete $closing{$id};
        }
        # Writes what the run's stdin takes now; a run that reads nothing never holds up the others.
        sub flush {
            my $id = shift;
            while (length $pending{$id}) {
                my $n = syswrite($input{$id}, $pending{$id});
                return if !defined $n && $!{EAGAIN};
                return close_input($id) unless defined $n;
                substr($pending{$id}, 0, $n) = '';
            }
            close_input($id) if $closing{$id};
        }
        sub command {
            my ($op, $id, $arg) = split / /, shift, 3;
            if ($op eq 'o') {
                my ($child_in, $in, $out, $child_out, $errors, $child_err);
                pipe($child_in, $in) && pipe($out, $child_out) && pipe($errors, $child_err)
                    or return put("x $id 127 \n");
                my $p = fork;
                if (defined $p && !$p) {
                    $SIG{PIPE} = 'DEFAULT';
                    open(STDIN, '<&', $child_in); open(STDOUT, '>&', $child_out); open(STDERR, '>&', $child_err);
                    exec('/bin/sh', '-c', pack('H*', $arg)) or POSIX::_exit(127);
                }
                close $_ for $child_in, $child_out, $child_err;
                return put("x $id 127 \n") unless defined $p;
                fcntl($in, F_SETFL, fcntl($in, F_GETFL, 0) | O_NONBLOCK);
                ($input{$id}, $pending{$id}, $pid{$id}, $err{$id}, $open{$id}) = ($in, '', $p, '', 2);
                $owner{fileno $out} = [$id, ''];
                $owner{fileno $errors} = [$id];
                $select->add($out, $errors);
            } elsif ($op eq 'w') { if ($input{$id}) { $pending{$id} .= "$arg\n"; flush($id) } }
            elsif ($op eq 'c') { if ($input{$id}) { $closing{$id} = 1; flush($id) } }
            # Its stdin too: a wrapper's background child ends with it (T6). The kill first: a wrapper that saw its
            # stdin close first could exit by itself (143, not 9).
            elsif ($op eq 'k') { kill 9, $pid{$id} if $pid{$id}; close_input($id) }
        }
        put("oriel-relay 1\n");
        while (1) {
            my $waiting = reap();
            my $writes = IO::Select->new(map { $input{$_} } grep { length $pending{$_} } keys %input);
            my ($readable, $writable) = IO::Select->select($select, $writes->count ? $writes : undef, undef,
                                                           $waiting ? 0.1 : undef);
            for my $fh (@{ $writable || [] }) {
                my ($id) = grep { $input{$_} && $input{$_} == $fh } keys %input;
                flush($id) if defined $id;
            }
            for my $fh (@{ $readable || [] }) {
                my $n = sysread($fh, my $chunk, 65536);
                # The app or the connection is gone: exiting closes every run's stdin, which ends it (T6).
                if (fileno $fh == 0) {
                    exit 0 unless $n;
                    $commands .= $chunk;
                    command($1) while $commands =~ s/^(.*)\n//;
                    next;
                }
                my $run = $owner{fileno $fh};
                my $id = $run->[0];
                if (!$n) {
                    $select->remove($fh); delete $owner{fileno $fh}; close $fh;
                    put("l $id $run->[1]\n") if defined $run->[1] && length $run->[1];
                    $open{$id}--;
                } elsif (@$run == 2) {
                    $run->[1] .= $chunk;
                    put("l $id $1\n") while $run->[1] =~ s/^(.*)\n//;
                } else {
                    $err{$id} = substr($err{$id} . $chunk, -8192);
                }
            }
        }
        """#
    }
#endif
