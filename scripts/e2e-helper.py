"""Runs herdr API requests for the sandboxed UI tests, which cannot reach herdr's sockets.

Usage: python3 scripts/e2e-helper.py <session>... -- <test command>...
Serves on 127.0.0.1 while the test command runs, then exits with its status.
POST /<session> with one API request line as the body; the reply line comes back.
POST /<session>/control with a terminal id as the body opens `terminal session control` on it
without takeover, closes its stdin at once (which lets go), and gives back what the stream printed
(a frame, or the reason it was refused); /<session>/takeover does the same with --takeover.
POST /<session>/children lists the session's `terminal session` and `remote-api-bridge` runs, one
command line each.
POST /<session>/stop stops the session; /<session>/start starts its server again, as a user would in a
terminal.
POST /<session>/open-folder with the built app's path as the body makes a folder in /tmp and opens it with the
app (`open -a`), as a drop on the Dock icon does; a launch gets `-session <session>` and the tests' config folder
(a running app ignores `--args`). The folder's path comes back.
POST /<session>/open-url with the built app's path, a newline and an ovvi:// URL opens the URL with that app (`open -g -a`;
a launch gets the tests' config folder).
POST /<session>/file-drag with "x y tx ty" (screen points) as the body makes a file whose name needs shell escaping in
a new folder in /tmp (its one line: ovvi-e2e-dropped), shows its icon at x y in a window of scripts/file-drag.swift
and drags it to tx ty (both points in an Ovvi window). The file's path comes back once a drop took it.
POST /<session>/temporary-file-drag does the same from a new NSIRD_ folder in $TMPDIR/TemporaryItems, as a
screenshot's floating thumbnail drops one.
POST /<session>/usage with a number of seconds as the body measures the app (the one process named Ovvi, on CI) over
that time: its footprint (`footprint`'s summary), its CPU and the session's `terminal session` runs, count and memory;
and the app's, WebKit's and all its processes' count, footprint, CPU, threads and interrupt wake-ups (scripts/usage.swift).
POST /<session>/ssh-drop with an SSH target as the body kills the app's ControlMaster to it (SIGKILL, as a crash
would), and gives back the pids it killed, one per line.
POST /<session>/ssh-forget with an SSH target as the body removes its host key from ~/.ssh/known_hosts, on CI only, so
ssh asks for it again.
POST /<session>/swipe with "x y step steps [pause [vertical [option]]]" as the body posts a two-finger trackpad swipe there (scripts/swipe.swift).
POST /<session>/drag with "x y (x y hold)..." as the body drags the mouse from the first point through the others,
holding at each (scripts/drag.swift).
POST /<session>/press with "x y tx ty" as the body drags from x y to tx ty and replies once it holds there;
/<session>/release lets go.
POST /<session>/stress with "tabs workspaces panes agents" as the body starts the session afresh and fills it with
scripts/stress.py; its summary comes back. With an empty body it removes the session, so the next tests do not run
beside its shells.
POST /<session>/sample with a number of seconds as the body gives back `sample`'s profile of the app over that time.
POST /<session>/heap gives back `heap`'s summary of the app's malloc heap, the largest classes first.
POST /<session>/pause stops the session's server (SIGSTOP), so the app's writes wait for herdr's answer;
/<session>/resume lets it go on (SIGCONT), as the helper's exit does for every session.
POST /<session>/ssh-connections gives back how many connections the CI sshd (scripts/ci-sshd.sh) has seen.
Any session not named on the command line is refused.
"""

import http.server
import os
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

split = sys.argv.index("--")
sessions, command = sys.argv[1:split], sys.argv[split + 1:]
folders = []
# Each session's drag that /press holds down until /release.
held = {}
# The tests' config folder (OvviUITests.noConfig): a launch from here installs the default plugins there, never in the
# user's ~/.config/ovvi.
NO_CONFIG = "/tmp/ovvi-e2e-no-config"
# The tests' config folder and agents' stores, never the user's (OvviUITests.noConfig).
ISOLATED = ["-configFolder", NO_CONFIG, "-archivedHome", "/tmp/ovvi-e2e-archived"]
# Compiled once, beside the app's build: `swift` interpreting the script again took up to 10 s a swipe on CI.
tools = tempfile.mkdtemp()
folders.append(tools)
builds = {name: subprocess.Popen(["swiftc", f"scripts/{name}.swift", "-o", f"{tools}/{name}"],
                                 stderr=open(f"{tools}/{name}.log", "wb")) for name in ("swipe", "drag", "file-drag", "usage")}


def cpu_seconds(pids):
    """The CPU time the processes used so far (`ps`'s [[h:]m:]s.cc)."""
    if not pids:
        return 0.0
    out = subprocess.run(["ps", "-o", "time=", "-p", ",".join(pids)], capture_output=True, text=True).stdout
    return sum(sum(float(part) * 60 ** index for index, part in enumerate(reversed(line.strip().split(":"))))
               for line in out.splitlines() if line.strip())


def usage(session, seconds):
    builds["usage"].wait()
    pid = subprocess.run(["pgrep", "-nx", "Ovvi"], capture_output=True, text=True).stdout.strip()
    pattern = f"^[^ ]*herdr --session {session} terminal session"
    helpers = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True).stdout.split()
    start, app_start, helpers_start = time.time(), cpu_seconds([pid]), cpu_seconds(helpers)
    # Over the same seconds: the app's and its processes' (WebKit's) count, CPU, threads and wake-ups.
    processes = subprocess.run([f"{tools}/usage", pid, str(seconds)], capture_output=True, text=True).stdout
    wall = time.time() - start
    app_cpu, helpers_cpu = cpu_seconds([pid]) - app_start, cpu_seconds(helpers) - helpers_start
    rss = subprocess.run(["ps", "-o", "rss=", "-p", ",".join(helpers)], capture_output=True, text=True).stdout \
        if helpers else ""
    summary = subprocess.run(["footprint", pid], capture_output=True, text=True).stdout.splitlines()
    return "\n".join([f"cpu {100 * app_cpu / wall:.1f}%",
                      f"helpers {len(helpers)} {sum(int(n) for n in rss.split()) // 1024} MB "
                      f"{100 * helpers_cpu / wall:.1f}%"] + processes.splitlines() + summary[:16]).encode()


def signal_server(session, action):
    """Stops (`pause`) the session's server or lets it go on (`resume`); false when no server matched."""
    return subprocess.run(["pkill", "-STOP" if action == "pause" else "-CONT", "-f",
                           f"^[^ ]*herdr --session {re.escape(session)} server$"], capture_output=True).returncode == 0


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        session, _, action = self.path.strip("/").partition("/")
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if session not in sessions:
            status, reply = 403, f"refusing session '{session}'".encode()
        elif action not in ("", "control", "takeover", "children", "stop", "start", "open-folder", "open-url",
                            "file-drag", "temporary-file-drag", "usage", "ssh-drop", "ssh-forget", "ssh-connections",
                            "swipe", "drag", "stress", "sample", "heap", "press", "release", "pause", "resume"):
            status, reply = 404, f"no action '{action}'".encode()
        elif action in ("control", "takeover") and not re.fullmatch(rb"\w[\w-]*", body):
            status, reply = 400, b"the body must be a terminal id"
        elif action in ("ssh-drop", "ssh-forget") and not re.fullmatch(rb"\w[\w-]*", body):
            status, reply = 400, b"the body must be an SSH target"
        elif action == "swipe" and not re.fullmatch(rb"-?[\d.]+( -?[\d.]+){3,6}", body):
            status, reply = 400, b"the body must be x y step steps [pause [vertical [option]]]"
        elif action == "stress" and not re.fullmatch(rb"(\d+ \d+ \d+ \d+)?", body):
            status, reply = 400, b"the body must be tabs workspaces panes agents, or empty"
        elif action == "stress":
            # Down first: a run cut short (a timeout, a test retried) may have left it.
            run = subprocess.run(["scripts/herdr-session.sh", "down", session], capture_output=True)
            if run.returncode == 0 and body:
                run = subprocess.run(["scripts/herdr-session.sh", "up", session], capture_output=True)
            if run.returncode == 0 and body:
                tabs, workspaces, panes, agents = body.decode().split()
                # This Mac's 511 terminals are shared with the user's own herdr sessions and programs.
                panes = panes if os.environ.get("CI") == "true" else str(min(int(panes), 200))
                try:
                    run = subprocess.run(["python3", "scripts/stress.py", session, tabs, workspaces, "--panes",
                                          panes, "--agents", agents], capture_output=True, timeout=280)
                except subprocess.TimeoutExpired as error:
                    run = subprocess.CompletedProcess(error.cmd, 1, b"", b"stress.py took over 280 s")
            status, reply = (200, run.stdout) if run.returncode == 0 else (500, run.stderr)
        elif action == "sample" and not re.fullmatch(rb"\d+", body):
            status, reply = 400, b"the body must be seconds"
        elif action in ("sample", "heap"):
            pid = subprocess.run(["pgrep", "-nx", "Ovvi"], capture_output=True, text=True).stdout.strip()
            argv = ["sample", pid, body.decode()] if action == "sample" else ["heap", "-s", "-H", "-q", pid]
            # A bound for a hung tool, not a measure: `heap` walks every malloc node, 37 s at the stress test's 400
            # panes on CI, and over 60 s on a runner half as fast.
            limit = 180
            try:
                run = subprocess.run(argv, capture_output=True, timeout=limit)
                status, reply = (200, run.stdout) if run.returncode == 0 else (500, run.stderr)
            except subprocess.TimeoutExpired:
                status, reply = 500, f"{action} took over {limit} s".encode()
        elif action == "drag" and not re.fullmatch(rb"-?[\d.]+ -?[\d.]+( -?[\d.]+ -?[\d.]+ [\d.]+)+", body):
            status, reply = 400, b"the body must be x y (x y hold)..."
        elif action in ("file-drag", "temporary-file-drag", "press") and not re.fullmatch(
                rb"-?[\d.]+( -?[\d.]+){3}", body):
            status, reply = 400, b"the body must be x y tx ty"
        elif action == "release" and session not in held:
            status, reply = 400, b"no drag held"
        elif action in (*builds, "press") and any([build.wait() for build in builds.values()]):
            status, reply = 500, b"".join(open(f"{tools}/{name}.log", "rb").read() for name in builds)
        elif action in ("swipe", "drag"):
            run = subprocess.run([f"{tools}/{action}"] + body.decode().split(), capture_output=True, timeout=120)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action == "press":
            run = subprocess.Popen([f"{tools}/drag"] + body.decode().split() + ["-1"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if run.stdout.readline():  # "held": over tx ty
                held[session] = run
                status, reply = 200, b""
            else:
                status, reply = 500, run.communicate(timeout=10)[1]
        elif action == "release":
            run = held.pop(session)
            _, error = run.communicate(b"\n", timeout=30)
            status, reply = (200, b"") if run.returncode == 0 else (500, error)
        elif action == "ssh-drop":
            pattern = f"ssh -M -N -f .* {body.decode()}$"
            pids = subprocess.run(["pgrep", "-f", pattern], capture_output=True).stdout
            subprocess.run(["pkill", "-9", "-f", pattern])
            status, reply = 200, pids
        elif action == "ssh-forget" and os.environ.get("CI") != "true":
            status, reply = 403, b"CI only: it writes ~/.ssh/known_hosts"
        elif action == "ssh-forget":
            run = subprocess.run(["ssh-keygen", "-R", body.decode()], capture_output=True)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action == "ssh-connections":
            try:
                with open("/tmp/ovvi-sshd/sshd.log") as log:
                    status, reply = 200, str(log.read().count("Connection from")).encode()
            except OSError as error:
                status, reply = 500, str(error).encode()
        elif action == "open-folder" and not body.endswith(b".app"):
            status, reply = 400, b"the body must be an app's path"
        elif action == "open-folder":
            folder = tempfile.mkdtemp(prefix="ovvi-e2e-drop-", dir="/tmp")
            folders.append(folder)
            run = subprocess.run(["open", "--env", "npm_config_offline=true", "-a", body.decode(), folder, "--args",
                                  "-session", session,
                                  "-ApplePersistenceIgnoreState", "YES", *ISOLATED],
                                 capture_output=True, timeout=10)
            status, reply = (200, folder.encode()) if run.returncode == 0 else (500, run.stderr)
        elif action == "open-url" and not re.fullmatch(rb"[^\n]+\.app\novvi://\S+", body):
            status, reply = 400, b"the body must be an app's path, a newline and an ovvi:// URL"
        elif action == "open-url":
            # As pi-herd opens it, to that app: LaunchServices may know other builds of the app.
            app, url = body.decode().split("\n")
            run = subprocess.run(["open", "--env", "npm_config_offline=true", "-g", "-a", app, url, "--args",
                                  "-machines", "[]", *ISOLATED],
                                 capture_output=True, timeout=10)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action in ("file-drag", "temporary-file-drag"):
            if action == "file-drag":
                folder = tempfile.mkdtemp(prefix="ovvi-e2e-file-", dir="/tmp")
            else:
                items = os.path.join(tempfile.gettempdir(), "TemporaryItems")
                os.makedirs(items, exist_ok=True)
                folder = tempfile.mkdtemp(prefix="NSIRD_ovvi-e2e_", dir=items)
            folders.append(folder)
            path = os.path.join(folder, "drop me's (1).txt")
            with open(path, "w") as file:
                file.write("ovvi-e2e-dropped\n")
            x, y, tx, ty = body.decode().split()
            source = subprocess.run([f"{tools}/file-drag", path, x, y, tx, ty], capture_output=True, timeout=30)
            status, reply = (200, path.encode()) if source.returncode == 0 else (
                500, source.stderr or b"the drop was refused")
        elif action in ("pause", "resume"):
            status, reply = (200, b"") if signal_server(session, action) else (500, b"no server")
        elif action == "usage":
            status, reply = 200, usage(session, float(body or b"10"))
        elif action == "start":
            env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
            subprocess.Popen(["herdr", "--session", session, "server"], env=env, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            status, reply = 200, b""
        else:
            argv = ["herdr", "--session", session]
            if action in ("control", "takeover"):
                argv += ["terminal", "session", "control", body.decode(), "--cols", "80", "--rows", "24"]
                argv += ["--takeover"] if action == "takeover" else []
                body = b""
            elif action == "children":
                # Tests ask while no other request of theirs runs, so none of these is the helper's own. Anchored:
                # the shell that wraps an `observe` run is not a run of its own.
                argv = ["pgrep", "-lf", f"^[^ ]*herdr --session {session} (terminal session|remote-api-bridge)"]
            elif action == "stop":
                argv = ["herdr", "session", "stop", session]
            else:
                argv += ["remote-api-bridge"]
            try:
                run = subprocess.run(argv, input=body, capture_output=True, timeout=10)
                # pgrep exits 1 when it finds none.
                ok = run.returncode == 0 or action == "children" and run.returncode == 1
                status, reply = (200, run.stdout) if ok else (500, run.stderr)
            except Exception as error:  # a timeout or no herdr: tell the test, keep serving
                status, reply = 500, str(error).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass


# Not HTTPServer: its getfqdn() lookup raised the Local Network prompt on CI. Threading: a test's `sample` runs while
# its swipes do.
server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
# xcodebuild passes TEST_RUNNER_* to the tests without the prefix.
# herdr's path: the agent test's stand-in login shell has no profile to find it.
env = {**os.environ, "TEST_RUNNER_OVVI_HELPER": f"http://127.0.0.1:{server.server_address[1]}",
       "TEST_RUNNER_OVVI_HERDR": shutil.which("herdr") or "",
       **{f"TEST_RUNNER_OVVI_SESSION{n if n > 1 else ''}": name for n, name in enumerate(sessions, 1)}}
status = subprocess.run(command, env=env).returncode
# A run cut short between a pause and its resume leaves no stopped server, which the cleanup's stop would wait on.
for name in sessions:
    signal_server(name, "resume")
for folder in folders:
    shutil.rmtree(folder, ignore_errors=True)
sys.exit(status)
