#!/usr/bin/env python3
"""pi's stand-in for the chat view's UI tests (CI has no pi).

Started by the chooser with Oriel's flags (`-e <pi-oriel-<sha8>.ts> --oriel <state file>`), it needs the extension
file whole (its sha256 starts with the name's sha8), writes the state lines pi-oriel writes and a session file in pi's
format, reports its state to herdr and answers prompts on its terminal: "wait" opens a dialog until 1 is typed, "slow"
works until Esc and takes a message sent meanwhile after its tool, as pi steers, "/tree" moves the leaf back before
the last user message, anything else gets one command and the reply "Echo: <prompt>".
"""
import hashlib
import json
import os
import select
import shutil
import signal
import subprocess
import sys
import termios
import time
import tty
import uuid

folder = os.path.join(os.environ.get("TMPDIR", "/tmp"), "oriel-stand-in")
os.makedirs(folder, exist_ok=True)
# herdr prompts an agent only while a process of its name runs in the foreground: run again as `pi`.
# A framework build's `python3` runs its Python.app, which would drop the name: link to that one.
if os.environ.get("ORIEL_STAND_IN") != "1":
    os.environ["ORIEL_STAND_IN"] = "1"
    app = os.path.join(sys.base_prefix, "Resources/Python.app/Contents/MacOS/Python")
    link = os.path.join(folder, "pi")
    if os.path.islink(link):
        os.remove(link)
    os.symlink(app if os.path.exists(app) else os.path.realpath(sys.executable), link)
    os.execv(link, [link, os.path.abspath(__file__)] + sys.argv[1:])
args = sys.argv[1:]
extension, state = args[args.index("-e") + 1], args[args.index("--oriel") + 1]
if not os.path.isfile(extension):
    sys.exit("Failed to load extension: Extension path does not exist: " + extension)
with open(extension, "rb") as file:
    if not os.path.basename(extension).endswith("-" + hashlib.sha256(file.read()).hexdigest()[:8] + ".ts"):
        sys.exit("The extension is not whole: " + extension)
os.makedirs(os.path.dirname(state), mode=0o700, exist_ok=True)
transcript = os.path.join(folder, os.path.basename(os.path.dirname(state)) + ".jsonl")
leaf = None


def report(state):
    subprocess.run([os.environ["HERDR_BIN_PATH"], "--session", os.environ["HERDR_SESSION"], "pane", "report-agent",
                    "--source", "oriel-e2e", "--agent", "pi", "--state", state, os.environ["HERDR_PANE_ID"]],
                   capture_output=True)


def line(path, value):
    with open(path, "a") as file:
        file.write(json.dumps(value) + "\n")


def entry(role, **fields):
    """Appends a message entry to the leaf, as pi does."""
    global leaf
    entry_id = uuid.uuid4().hex[:8]
    line(transcript, {"type": "message", "id": entry_id, "parentId": leaf,
                      "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                      "message": {"role": role, "timestamp": int(time.time() * 1000), **fields}})
    leaf = entry_id
    return entry_id


def say(text):
    sys.stdout.write(text.replace("\n", "\r\n") + "\r\n")
    sys.stdout.flush()


def key(timeout=None):
    """The next input, without its bracketed paste marks; "" after `timeout`."""
    if not select.select([0], [], [], timeout)[0]:
        return ""
    data = os.read(0, 4096).decode(errors="replace")
    return data.replace("\x1b[200~", "").replace("\x1b[201~", "")


def assistant(content, stop, **fields):
    entry("assistant", content=content, api="stand-in", provider="stand-in", model="pi-stand-in", stopReason=stop,
          **fields)


def prompt(text):
    if text == "/tree":
        # Back to the parent of the last user entry, as picking it in /tree does.
        entries = {}
        with open(transcript) as file:
            for row in file:
                value = json.loads(row)
                entries[value.get("id")] = value
        global leaf
        node = entries.get(leaf)
        while node and node.get("message", {}).get("role") != "user":
            node = entries.get(node.get("parentId"))
        if node:
            leaf = node.get("parentId")
            line(state, {"type": "tree", "leaf": leaf, "at": os.path.getsize(transcript)})
        say("Navigated to selected point")
        return
    entry("user", content=[{"type": "text", "text": text}])
    line(state, {"type": "working"})
    report("working")
    if text == "wait":
        line(state, {"type": "blocked"})
        report("blocked")
        say("Allow this command?\n  1. Yes\n  2. No")
        while "1" not in key():
            pass
        line(state, {"type": "unblocked"})
        report("working")
        assistant([{"type": "text", "text": "Allowed."}], "stop")
    elif text == "slow":
        call = "toolu_" + uuid.uuid4().hex[:12]
        assistant([{"type": "toolCall", "id": call, "name": "bash", "arguments": {"command": "sleep 30"}}], "toolUse")
        deadline, typed = time.time() + 30, ""
        while time.time() < deadline:
            data = key(deadline - time.time())
            if "\x1b" in data:
                break
            typed += data
        entry("toolResult", toolCallId=call, toolName="bash", content=[{"type": "text", "text": "Killed: 9"}],
              isError=True)
        for steer in typed.split("\r")[:-1]:
            entry("user", content=[{"type": "text", "text": steer.strip()}])
        assistant([], "error", errorMessage="The operation was aborted.")
        say("Interrupted")
    else:
        time.sleep(0.5)
        call = "toolu_" + uuid.uuid4().hex[:12]
        assistant([{"type": "toolCall", "id": call, "name": "bash", "arguments": {"command": "echo " + text}}],
                  "toolUse")
        entry("toolResult", toolCallId=call, toolName="bash", content=[{"type": "text", "text": text}], isError=False)
        assistant([{"type": "text", "text": "Echo: **" + text + "**"}], "stop")
        say("Echo: **" + text + "**")
    line(state, {"type": "idle"})
    report("idle")


def main():
    # A closed pane hangs up: clean up as on Ctrl-C.
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    line(transcript, {"type": "session", "version": 3, "id": str(uuid.uuid4()),
                      "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), "cwd": os.getcwd()})
    line(state, {"type": "session", "path": transcript})
    attributes = termios.tcgetattr(0)
    tty.setraw(0)
    # Bracketed paste on, as pi has it: herdr's agent.prompt pastes, then presses Enter.
    sys.stdout.write("\x1b[?2004h")
    say("pi stand-in " + state)
    report("idle")
    text = ""
    try:
        while True:
            data = key()
            if "\x03" in data or "\x04" in data:
                break
            text += data.replace("\x1b", "")
            if "\r" not in text:
                sys.stdout.write(data.replace("\x1b", ""))
                sys.stdout.flush()
                continue
            text, rest = text.split("\r", 1)
            say("")
            if text.strip():
                prompt(text.strip())
            text = rest
    finally:
        # What it wrote goes with it; first, as a hung-up terminal takes no settings. A second hang-up would stop it
        # halfway.
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        line(state, {"type": "shutdown"})
        if os.path.exists(transcript):
            os.remove(transcript)
        shutil.rmtree(os.path.dirname(state), ignore_errors=True)
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)


main()
