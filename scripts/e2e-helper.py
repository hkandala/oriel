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


def app_pid():
    return subprocess.run(["pgrep", "-nx", "Oriel"], capture_output=True, text=True).stdout.strip()


def cpu_seconds(pids):
    """The CPU time the processes used so far (`ps`'s [[h:]m:]s.cc)."""
    if not pids:
        return 0.0
    out = subprocess.run(["ps", "-o", "time=", "-p", ",".join(pids)], capture_output=True, text=True).stdout
    return sum(sum(float(part) * 60 ** index for index, part in enumerate(reversed(line.strip().split(":"))))
               for line in out.splitlines() if line.strip())


def usage(session, seconds):
    pid = app_pid()
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
        elif action not in ("", "control", "takeover", "children", "stop", "start", "open-folder",
                            "reveal-file", "usage", "ssh-drop", "ssh-connections"):
            status, reply = 404, f"no action '{action}'".encode()
        elif action in ("control", "takeover") and not re.fullmatch(rb"\w[\w-]*", body):
            status, reply = 400, b"the body must be a terminal id"
        elif action == "ssh-drop" and not re.fullmatch(rb"\w[\w-]*", body):
            status, reply = 400, b"the body must be an SSH target"
        elif action == "ssh-drop":
            pattern = f"ssh -M -N -f .* {body.decode()}$"
            pids = subprocess.run(["pgrep", "-f", pattern], capture_output=True).stdout
            subprocess.run(["pkill", "-9", "-f", pattern])
            status, reply = 200, pids
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
