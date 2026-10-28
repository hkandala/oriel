#!/usr/bin/env python3
"""Codex's stand-in for the chat view's UI tests (CI has no Codex).

Started by the chooser with Oriel's flags (`-c hooks.SessionStart=… -c hooks.state=…`), it checks the hook's trust
hash as Codex does (else it shows Codex's "Hooks need review" picker and runs no hook), runs the hook at the first
prompt, writes a rollout in Codex's format, reports its state to herdr and draws Codex's input box above its status
row. Prompts: "wait" shows an approval until 1 is typed, "model" opens a picker (herdr still says idle) until Esc,
"slow" works until Esc, "new" starts a new session (as `/new` and a prompt do), anything else gets one command and
the reply "Echo: <prompt>".
"""
import hashlib
import json
import os
import re
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
# herdr prompts an agent only while a process of its name runs in the foreground: run again as `codex`.
# A framework build's `python3` runs its Python.app, which would drop the name: link to that one.
if os.environ.get("ORIEL_STAND_IN") != "1":
    os.environ["ORIEL_STAND_IN"] = "1"
    app = os.path.join(sys.base_prefix, "Resources/Python.app/Contents/MacOS/Python")
    link = os.path.join(folder, "codex")
    if os.path.islink(link):
        os.remove(link)
    os.symlink(app if os.path.exists(app) else os.path.realpath(sys.executable), link)
    os.execv(link, [link, os.path.abspath(__file__)] + sys.argv[1:])
values = [sys.argv[i + 1] for i, arg in enumerate(sys.argv[:-1]) if arg == "-c"]
hook = re.search(r'command="([^"]*)"', next(v for v in values if v.startswith("hooks.SessionStart="))).group(1)
trusted = re.search(r'trusted_hash="([^"]*)"', next(v for v in values if v.startswith("hooks.state="))).group(1)
# Codex's hash of a hook: sha256 of its sorted compact JSON, with the defaults filled in.
identity = {"event_name": "session_start",
            "hooks": [{"async": False, "command": hook, "timeout": 600, "type": "command"}]}
trusts = trusted == "sha256:" + hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":"))
                                               .encode()).hexdigest()
token = re.search(r"/\.cache/oriel/chat/([0-9a-f-]{36})/", hook).group(1)
rollouts = []


def report(state):
    subprocess.run([os.environ["HERDR_BIN_PATH"], "--session", os.environ["HERDR_SESSION"], "pane", "report-agent",
                    "--source", "oriel-e2e", "--agent", "codex", "--state", state, os.environ["HERDR_PANE_ID"]],
                   capture_output=True)


def write(kind, **payload):
    line = {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), "type": kind, "payload": payload}
    with open(rollouts[-1], "a") as file:
        file.write(json.dumps(line) + "\n")


def item(kind, **fields):
    write("event_msg", type="item_completed", item={"type": kind, "id": str(uuid.uuid4()), **fields})


def say(text):
    sys.stdout.write(text.replace("\n", "\r\n") + "\r\n")
    sys.stdout.flush()


def box():
    say("\n› Ask Codex to do anything\n\n  stand-in high · " + os.getcwd() + "\n  ? for shortcuts")


def key(timeout=None):
    """The next input, without its bracketed paste marks; "" after `timeout`."""
    if not select.select([0], [], [], timeout)[0]:
        return ""
    data = os.read(0, 4096).decode(errors="replace")
    return data.replace("\x1b[200~", "").replace("\x1b[201~", "")


def prompt(text, started):
    if not rollouts or text == "new":
        # Codex starts its session at the first prompt, and a hidden thread with no rollout.
        thread = str(uuid.uuid4())
        rollouts.append(os.path.join(folder, "rollout-" + thread + ".jsonl"))
        write("session_meta", id=thread, source="cli", cli_version="0.163.0", cwd=os.getcwd())
        for path in [rollouts[-1], None]:
            subprocess.run([os.environ.get("SHELL", "/bin/sh"), "-lc", hook], capture_output=True, input=json.dumps(
                {"session_id": thread, "transcript_path": path, "cwd": os.getcwd(), "hook_event_name": "SessionStart",
                 "model": "stand-in", "source": "startup"}), text=True)
    turn = str(uuid.uuid4())
    write("event_msg", type="task_started", turn_id=turn)
    write("turn_context", turn_id=turn, cwd=os.getcwd(), model="codex-stand-in", effort="high")
    item("UserMessage", content=[{"type": "text", "text": text}])
    report("working")
    if text == "wait":
        report("blocked")
        say("  Would you like to run the following command?\n› 1. Yes, proceed (y)\n  2. No (esc)\n"
            "  Press enter to confirm or esc to cancel")
        while "1" not in key():
            pass
        report("working")
        item("AgentMessage", content=[{"type": "Text", "text": "Allowed."}], phase="final_answer")
    elif text == "model":
        report("idle")
        say("  Select Model and Effort\n› 1. stand-in (current)\n  2. other\n  enter select · esc back")
        while "\x1b" not in key():
            pass
        box()
        return
    elif text == "slow":
        box()
        deadline = time.time() + 30
        while time.time() < deadline and "\x1b" not in key(deadline - time.time()):
            pass
        write("event_msg", type="turn_aborted", turn_id=turn, reason="interrupted")
        report("idle")
        say("■ Conversation interrupted")
        box()
        return
    else:
        time.sleep(0.5)
        item("CommandExecution", command=["/bin/zsh", "-lc", "echo " + text], parsed_cmd=[], status="completed",
             aggregated_output=text + "\n", exit_code=0, duration={"secs": 0, "nanos": 1000})
        item("AgentMessage", content=[{"type": "Text", "text": "Echo: **" + text + "**"}], phase="final_answer")
    write("event_msg", type="task_complete", turn_id=turn, duration_ms=int((time.time() - started) * 1000))
    report("idle")
    say("• done")
    box()


def main():
    # A closed pane hangs up: clean up as on Ctrl-C.
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    attributes = termios.tcgetattr(0)
    tty.setraw(0)
    # Bracketed paste on, as Codex has it: herdr's agent.prompt pastes, then presses Enter.
    sys.stdout.write("\x1b[?2004h")
    say("Codex stand-in " + token)
    if not trusts:
        say("  Hooks need review\n› 1. Review hooks\n  2. Trust all\n  enter select · esc back")
    else:
        box()
    report("idle")
    line = ""
    try:
        while True:
            data = key()
            if "\x03" in data or "\x04" in data:
                break
            line += data.replace("\x1b", "")
            if "\r" not in line:
                continue
            text, line = line.split("\r", 1)
            if trusts and text.strip():
                prompt(text.strip(), time.time())
    finally:
        # What it and its hook wrote goes with it; first, as a hung-up terminal takes no settings. A second hang-up
        # would stop it halfway.
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        for rollout in rollouts:
            os.remove(rollout)
        shutil.rmtree(os.path.expanduser("~/.cache/oriel/chat/" + token), ignore_errors=True)
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)


main()
