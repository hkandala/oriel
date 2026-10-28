#!/usr/bin/env python3
"""OpenCode's stand-in for the chat view's UI tests (CI has no OpenCode).

Started by the chooser with Oriel's line (`--port 0 --hostname 127.0.0.1 -- oriel-T`, the password and the TUI config
in the environment), it runs opencode 1.x's server shapes on 127.0.0.1 behind Basic auth (the history, `/event`, the
permission and question requests and their replies), appends the state lines Oriel's TUI plugin would (only when
the config names the plugin file), reports its state to herdr and answers prompts on its terminal: "allow" asks a
permission, "ask" a question, "pick" opens a dialog until 1 is typed, "slow" works until Esc Esc, "mute" drops the
next prompt, anything else gets one command and the reply "Echo: <prompt>".
"""
import base64
import http.server
import itertools
import json
import os
import queue
import select
import signal
import subprocess
import sys
import termios
import threading
import time
import tty

folder = os.path.join(os.environ.get("TMPDIR", "/tmp"), "oriel-stand-in")
os.makedirs(folder, exist_ok=True)
# herdr prompts an agent only while a process of its name runs in the foreground: run again as `opencode`.
if os.environ.get("ORIEL_STAND_IN") != "1":
    os.environ["ORIEL_STAND_IN"] = "1"
    app = os.path.join(sys.base_prefix, "Resources/Python.app/Contents/MacOS/Python")
    link = os.path.join(folder, "opencode")
    if os.path.islink(link):
        os.remove(link)
    os.symlink(app if os.path.exists(app) else os.path.realpath(sys.executable), link)
    os.execv(link, [link, os.path.abspath(__file__)] + sys.argv[1:])

password = os.environ["OPENCODE_SERVER_PASSWORD"]
state_file = os.environ.get("ORIEL_OC_STATE")
with open(os.environ["OPENCODE_TUI_CONFIG"]) as config:
    plugged = all(os.path.exists(path) for path in json.load(config)["plugin"])
ids = itertools.count(1)
messages, requests, clients = [], {}, []
lock = threading.Lock()
replied = threading.Condition(lock)
answers = {}
session = None


def new_id(kind):
    return "%s_%012d" % (kind, next(ids))


def now():
    return int(time.time() * 1000)


def publish(kind, **properties):
    event = "data: " + json.dumps({"id": new_id("evt"), "type": kind, "properties": properties}) + "\n\n"
    with lock:
        for client in clients:
            client.put(event)


def message(role, **info):
    entry = {"info": {"id": new_id("msg"), "sessionID": session, "role": role, "time": {"created": now()},
                      "modelID": "opencode-stand-in", **info}, "parts": []}
    messages.append(entry)
    publish("message.updated", sessionID=session, info=entry["info"])
    return entry


def part(entry, kind, **fields):
    value = {"id": new_id("prt"), "sessionID": session, "messageID": entry["info"]["id"], "type": kind, **fields}
    entry["parts"].append(value)
    publish("message.part.updated", sessionID=session, part=value)
    return value


def update(entry, value):
    publish("message.part.updated", sessionID=session, part=value)


def finish(entry, **fields):
    entry["info"]["time"]["completed"] = now()
    entry["info"].update(fields)
    publish("message.updated", sessionID=session, info=entry["info"])


def status(kind):
    publish("session.status", sessionID=session, status={"type": kind})
    if kind == "idle":
        publish("session.idle", sessionID=session)


def write_state(dialog=False):
    if state_file and plugged:
        line = {"pid": os.getpid(), "url": url, "session": session, "dialog": dialog}
        with open(state_file, "a") as file:
            file.write(json.dumps(line) + "\n")


class Server(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, code, value):
        body = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def allowed(self):
        expected = "Basic " + base64.b64encode(("opencode:" + password).encode()).decode()
        if self.headers.get("authorization") == expected:
            return True
        self.reply(401, {"error": "unauthorized"})
        return False

    def do_GET(self):
        if not self.allowed():
            return
        path = self.path.split("?")[0]
        if path == "/event":
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            events = queue.Queue()
            events.put("data: " + json.dumps({"type": "server.connected", "properties": {}}) + "\n\n")
            with lock:
                clients.append(events)
            try:
                while True:
                    self.wfile.write(events.get().encode())
                    self.wfile.flush()
            except OSError:
                with lock:
                    clients.remove(events)
        elif path == "/session/%s/message" % session:
            self.reply(200, messages)
        elif path in ("/permission", "/question"):
            with lock:
                self.reply(200, [r for r in requests.values() if r["id"].startswith(path[1:4])])
        else:
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        if not self.allowed():
            return
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        parts = self.path.split("/")
        with lock:
            found = len(parts) == 4 and parts[3] == "reply" and parts[2] in requests
            if found:
                del requests[parts[2]]
                answers[parts[2]] = body
                replied.notify_all()
        if not found:
            self.reply(404, {"_tag": "NotFoundError"})
            return
        self.reply(200, True)


def ask(kind, request):
    """Asks through the server and waits for the reply (the chat's), or for 1 typed in the terminal."""
    request_id = new_id(kind[:3])
    request = {"id": request_id, "sessionID": session, **request}
    with lock:
        requests[request_id] = request
    publish(kind + ".asked", **request)
    while True:
        with lock:
            if request_id in answers:
                break
        if "1" in key(0.1):
            with lock:
                requests.pop(request_id, None)
                answers[request_id] = {"reply": "once"} if kind == "permission" else {"answers": [["Red"]]}
            break
    with lock:
        answer = answers.pop(request_id)
    publish(kind + ".replied", sessionID=session, requestID=request_id, **answer)
    return answer


def report(state):
    subprocess.run([os.environ["HERDR_BIN_PATH"], "--session", os.environ["HERDR_SESSION"], "pane", "report-agent",
                    "--source", "oriel-e2e", "--agent", "opencode", "--state", state, os.environ["HERDR_PANE_ID"]],
                   capture_output=True)


def say(text):
    sys.stdout.write(text.replace("\n", "\r\n") + "\r\n")
    sys.stdout.flush()


def key(timeout=None):
    """The next input, without its bracketed paste marks; "" after `timeout`."""
    if not select.select([0], [], [], timeout)[0]:
        return ""
    data = os.read(0, 4096).decode(errors="replace")
    return data.replace("\x1b[200~", "").replace("\x1b[201~", "")


def command(entry, text, output):
    tool = part(entry, "tool", tool="bash", callID=new_id("call"),
                state={"status": "running", "input": {"command": text}, "time": {"start": now()}})
    if output is not None:
        tool["state"] = {"status": "completed", "input": {"command": text}, "output": output, "title": text,
                         "metadata": {"exit": 0}, "time": {"start": tool["state"]["time"]["start"], "end": now()}}
        update(entry, tool)
    return tool


def answer(entry, text):
    part(entry, "text", text=text, time={"start": now(), "end": now()})
    finish(entry, finish="stop")
    status("idle")
    report("idle")
    say(text)


def prompt(text):
    global session
    if session is None:
        session = new_id("ses")
        write_state()
    user = message("user")
    part(user, "text", text=text)
    status("busy")
    report("working")
    entry = message("assistant", parentID=user["info"]["id"])
    if text == "allow":
        report("blocked")
        say("Permission required: touch allowed.txt  1. Allow once")
        tool = command(entry, "touch allowed.txt", None)
        reply = ask("permission", {"permission": "bash", "patterns": ["touch allowed.txt"],
                                   "metadata": {"command": "touch allowed.txt"}, "always": ["touch *"],
                                   "tool": {"messageID": entry["info"]["id"], "callID": tool["callID"]}})["reply"]
        report("working")
        tool["state"] = {"status": "completed" if reply != "reject" else "error", "input": tool["state"]["input"],
                         "output": "", "error": "Rejected", "time": {"start": tool["state"]["time"]["start"],
                                                                      "end": now()}}
        update(entry, tool)
        answer(entry, "Allowed." if reply != "reject" else "Rejected.")
    elif text == "ask":
        report("blocked")
        say("Which color? 1. Red 2. Blue")
        chosen = ask("question", {"questions": [{"question": "Which color?", "header": "Color", "options": [
            {"label": "Red", "description": ""}, {"label": "Blue", "description": ""}]}]})["answers"][0][0]
        report("working")
        answer(entry, "You chose " + chosen + ".")
    elif text == "pick":
        write_state(dialog=True)
        say("Select model  1. Stand-in")
        while "1" not in key():
            pass
        write_state()
        answer(entry, "Picked.")
    elif text == "slow":
        command(entry, "sleep 30", None)
        deadline, escapes = time.time() + 30, 0
        while time.time() < deadline and escapes < 2:
            escapes += key(deadline - time.time()).count("\x1b")
        finish(entry, error={"name": "MessageAbortedError", "data": {"message": "Aborted"}})
        status("idle")
        report("idle")
        say("interrupted")
    else:
        time.sleep(0.5)
        command(entry, "echo " + text, text)
        answer(entry, "Echo: **" + text + "**")


def main():
    global url
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
    server.daemon_threads = True
    url = "http://127.0.0.1:%d" % server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # A closed pane hangs up: clean up as on Ctrl-C.
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    attributes = termios.tcgetattr(0)
    tty.setraw(0)
    sys.stdout.write("\x1b[?2004h")
    say("OpenCode stand-in " + url)
    write_state()
    report("idle")
    line, mute = "", False
    try:
        while True:
            data = key()
            if "\x03" in data or "\x04" in data:
                break
            line += data.replace("\x1b", "")
            if "\r" not in line:
                sys.stdout.write(data.replace("\x1b", ""))
                sys.stdout.flush()
                continue
            text, line = line.split("\r", 1)
            say("")
            if mute:
                mute = False
            elif text.strip():
                prompt(text.strip())
                mute = text.strip() == "mute"
    finally:
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        if state_file:
            subprocess.run(["rm", "-rf", os.path.dirname(state_file)])
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)


main()
