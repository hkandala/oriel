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
app (`open -a`), as a drop on the Dock icon does; a launch gets `-session <session>` (a running app ignores
`--args`). The folder's path comes back.
POST /<session>/reveal-file makes a file whose name needs shell escaping in a new folder in /tmp and shows it in a Finder
window (`open -R`), for a drag from Finder. The file's path comes back.
POST /<session>/usage with a number of seconds as the body measures the app (the one process named Oriel, on CI) over
that time: its footprint (`footprint`'s summary), its CPU and the session's `terminal session` runs, count and memory.
POST /<session>/ssh-drop with an SSH target as the body kills the app's ControlMaster to it (SIGKILL, as a crash
would), and gives back the pids it killed, one per line.
POST /<session>/ssh-forget with an SSH target as the body removes its host key from ~/.ssh/known_hosts, on CI only, so
ssh asks for it again.
POST /<session>/swipe with "x y step steps [pause [vertical [option]]]" as the body posts a two-finger trackpad swipe there (scripts/swipe.swift).
POST /<session>/drag with "x y (x y hold)..." as the body drags the mouse from the first point through the others,
holding at each (scripts/drag.swift).
POST /<session>/stress with "tabs workspaces panes agents" as the body starts the session afresh and fills it with
scripts/stress.py; its summary comes back. With an empty body it removes the session, so the next tests do not run
beside its shells.
POST /<session>/sample with a number of seconds as the body gives back `sample`'s profile of the app over that time.
POST /<session>/heap gives back `heap`'s summary of the app's malloc heap, the largest classes first.
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


def cpu_seconds(pids):
    """The CPU time the processes used so far (`ps`'s [[h:]m:]s.cc)."""
    if not pids:
        return 0.0
    out = subprocess.run(["ps", "-o", "time=", "-p", ",".join(pids)], capture_output=True, text=True).stdout
    return sum(sum(float(part) * 60 ** index for index, part in enumerate(reversed(line.strip().split(":"))))
               for line in out.splitlines() if line.strip())


def usage(session, seconds):
    pid = subprocess.run(["pgrep", "-nx", "Oriel"], capture_output=True, text=True).stdout.strip()
    pattern = f"^[^ ]*herdr --session {session} terminal session"
    helpers = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True).stdout.split()
    start, app_start, helpers_start = time.time(), cpu_seconds([pid]), cpu_seconds(helpers)
    time.sleep(seconds)
    wall = time.time() - start
    app_cpu, helpers_cpu = cpu_seconds([pid]) - app_start, cpu_seconds(helpers) - helpers_start
    rss = subprocess.run(["ps", "-o", "rss=", "-p", ",".join(helpers)], capture_output=True, text=True).stdout \
        if helpers else ""
    summary = subprocess.run(["footprint", pid], capture_output=True, text=True).stdout.splitlines()
    return "\n".join([f"cpu {100 * app_cpu / wall:.1f}%",
                      f"helpers {len(helpers)} {sum(int(n) for n in rss.split()) // 1024} MB "
                      f"{100 * helpers_cpu / wall:.1f}%"] + summary[:16]).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        session, _, action = self.path.strip("/").partition("/")
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if session not in sessions:
            status, reply = 403, f"refusing session '{session}'".encode()
        elif action not in ("", "control", "takeover", "children", "stop", "start", "open-folder", "open-url",
                            "reveal-file", "usage", "ssh-drop", "ssh-forget", "ssh-connections", "swipe", "drag",
                            "stress", "sample", "heap"):
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
            pid = subprocess.run(["pgrep", "-nx", "Oriel"], capture_output=True, text=True).stdout.strip()
            argv = ["sample", pid, body.decode()] if action == "sample" else ["heap", "-s", "-H", "-q", pid]
            try:
                run = subprocess.run(argv, capture_output=True, timeout=60)
                status, reply = (200, run.stdout) if run.returncode == 0 else (500, run.stderr)
            except subprocess.TimeoutExpired:
                status, reply = 500, f"{action} took over 60 s".encode()
        elif action == "drag" and not re.fullmatch(rb"-?[\d.]+ -?[\d.]+( -?[\d.]+ -?[\d.]+ [\d.]+)+", body):
            status, reply = 400, b"the body must be x y (x y hold)..."
        elif action in ("swipe", "drag"):
            run = subprocess.run(["swift", f"scripts/{action}.swift"] + body.decode().split(), capture_output=True,
                                 timeout=120)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
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
                with open("/tmp/oriel-sshd/sshd.log") as log:
                    status, reply = 200, str(log.read().count("Connection from")).encode()
            except OSError as error:
                status, reply = 500, str(error).encode()
        elif action == "open-folder" and not body.endswith(b".app"):
            status, reply = 400, b"the body must be an app's path"
        elif action == "open-folder":
            folder = tempfile.mkdtemp(prefix="oriel-e2e-drop-", dir="/tmp")
            folders.append(folder)
            run = subprocess.run(["open", "-a", body.decode(), folder, "--args", "-session", session,
                                  "-ApplePersistenceIgnoreState", "YES"], capture_output=True, timeout=10)
            status, reply = (200, folder.encode()) if run.returncode == 0 else (500, run.stderr)
        elif action == "open-url" and not re.fullmatch(rb"[^\n]+\.app\noriel://\S+", body):
            status, reply = 400, b"the body must be an app's path, a newline and an oriel:// URL"
        elif action == "open-url":
            # As pi-herd opens it, to that app: LaunchServices may know other builds of the app.
            app, url = body.decode().split("\n")
            run = subprocess.run(["open", "-g", "-a", app, url], capture_output=True, timeout=10)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action == "reveal-file":
            folder = tempfile.mkdtemp(prefix="oriel-e2e-file-", dir="/tmp")
            folders.append(folder)
            path = os.path.join(folder, "drop me's (1).txt")
            open(path, "w").close()
            run = subprocess.run(["open", "-R", path], capture_output=True, timeout=10)
            status, reply = (200, path.encode()) if run.returncode == 0 else (500, run.stderr)
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
                # The helper runs one request at a time, so none of these is its own. Anchored: the shell that
                # wraps an `observe` run is not a run of its own.
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


# Not HTTPServer: its getfqdn() lookup raised the Local Network prompt on CI.
server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
# xcodebuild passes TEST_RUNNER_* to the tests without the prefix.
env = {**os.environ, "TEST_RUNNER_ORIEL_HELPER": f"http://127.0.0.1:{server.server_address[1]}",
       **{f"TEST_RUNNER_ORIEL_SESSION{n if n > 1 else ''}": name for n, name in enumerate(sessions, 1)}}
status = subprocess.run(command, env=env).returncode
for folder in folders:
    shutil.rmtree(folder, ignore_errors=True)
sys.exit(status)
