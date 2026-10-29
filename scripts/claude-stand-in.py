#!/usr/bin/env python3
"""Claude Code's stand-in for the chat view's UI tests (CI has no Claude Code).

Started by the chooser with Oriel's flags (`--session-id T --settings <json>`), it runs the settings' own hooks,
writes a transcript in Claude Code's format, reports its state to herdr and answers prompts on its terminal: "wait"
shows a dialog until 1 is typed, "ask" asks a question through the PermissionRequest hook, "slow" works until Esc,
"mute" drops the next prompt, anything else gets one command and the reply "Echo: <prompt>". Ctrl-C clears the line,
and on an empty one asks for another; "/exit" quits. Started without flags it reports its session to herdr (as
herdr's Claude Code integration does) and keeps its transcript, which `--resume <session>` goes on with.
"""
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
# herdr prompts an agent only while a process of its name runs in the foreground: run again as `claude`.
# A framework build's `python3` runs its Python.app, which would drop the name: link to that one.
if os.environ.get("ORIEL_STAND_IN") != "1":
    os.environ["ORIEL_STAND_IN"] = "1"
    app = os.path.join(sys.base_prefix, "Resources/Python.app/Contents/MacOS/Python")
    link = os.path.join(folder, "claude")
    if os.path.islink(link):
        os.remove(link)
    os.symlink(app if os.path.exists(app) else os.path.realpath(sys.executable), link)
    os.execv(link, [link, os.path.abspath(__file__)] + sys.argv[1:])
args = sys.argv[1:]
settings = args[args.index("--settings") + 1] if "--settings" in args else '{"hooks":{}}'
hooks = json.loads(settings)["hooks"]
resumed = "--resume" in args
token = args[args.index("--resume" if resumed else "--session-id") + 1] if resumed or "--session-id" in args \
    else str(uuid.uuid4())
transcript = os.path.join(folder, token + ".jsonl")


def hook(event, payload):
    """Runs the event's hook as Claude Code does (its JSON on stdin) and gives back what it printed."""
    for group in hooks.get(event, []):
        for command in group["hooks"]:
            return subprocess.run(["sh", "-c", command["command"]], input=json.dumps(payload),
                                  capture_output=True, text=True).stdout
    return ""


def herdr(*arguments):
    subprocess.run([os.environ["HERDR_BIN_PATH"], "--session", os.environ["HERDR_SESSION"], "pane", *arguments,
                    os.environ["HERDR_PANE_ID"]], capture_output=True)


def report(state):
    herdr("report-agent", "--source", "oriel-e2e", "--agent", "claude", "--state", state)


def write(kind, **fields):
    line = {"type": kind, "uuid": str(uuid.uuid4()), "cwd": os.getcwd(),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), **fields}
    with open(transcript, "a") as file:
        file.write(json.dumps(line) + "\n")


def say(text):
    sys.stdout.write(text.replace("\n", "\r\n") + "\r\n")
    sys.stdout.flush()


def key(timeout=None):
    """The next input, without its bracketed paste marks; "" after `timeout`."""
    if not select.select([0], [], [], timeout)[0]:
        return ""
    data = os.read(0, 4096).decode(errors="replace")
    return data.replace("\x1b[200~", "").replace("\x1b[201~", "")


def tool(command, output):
    tool_id = "toolu_" + uuid.uuid4().hex[:12]
    write("assistant", message={"model": "claude-stand-in", "content": [
        {"type": "tool_use", "id": tool_id, "name": "Bash", "input": {"command": command}}]})
    if output is not None:
        write("user", message={"content": [{"type": "tool_result", "tool_use_id": tool_id, "content": output}]})


def reply(text, started):
    write("assistant", message={"model": "claude-stand-in", "content": [{"type": "text", "text": text}]})
    write("system", subtype="turn_duration", durationMs=int((time.time() - started) * 1000))
    report("idle")
    say(text)


def prompt(text, started):
    write("user", message={"content": text})
    report("working")
    if text == "wait":
        report("blocked")
        say("Allow this command?\n  1. Yes\n  2. No")
        while "1" not in key():
            pass
        report("working")
        reply("Allowed.", started)
    elif text == "ask":
        questions = [{"question": "Which fruit?", "header": "Fruit", "multiSelect": False,
                      "options": [{"label": "Apple", "description": ""}, {"label": "Pear", "description": ""}]}]
        report("blocked")
        say("Which fruit? 1. Apple 2. Pear")
        decision = hook("PermissionRequest", {"session_id": token, "hook_event_name": "PermissionRequest",
                                              "tool_name": "AskUserQuestion", "tool_input": {"questions": questions}})
        answers = json.loads(decision)["hookSpecificOutput"]["decision"]["updatedInput"]["answers"]
        report("working")
        reply("You chose " + answers["Which fruit?"] + ".", started)
    elif text == "slow":
        tool("sleep 30", None)
        deadline = time.time() + 30
        while time.time() < deadline and "\x1b" not in key(deadline - time.time()):
            pass
        write("user", message={"content": "[Request interrupted by user]"})
        report("idle")
        say("Interrupted")
    else:
        time.sleep(0.5)
        tool("echo " + text, text)
        reply("Echo: **" + text + "**", started)


def main():
    # A closed pane hangs up: clean up as on Ctrl-C.
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    hook("SessionStart", {"session_id": token, "transcript_path": transcript, "cwd": os.getcwd(),
                          "hook_event_name": "SessionStart", "source": "resume" if resumed else "startup"})
    attributes = termios.tcgetattr(0)
    tty.setraw(0)
    # Bracketed paste on, as Claude Code has it: herdr's agent.prompt pastes, then presses Enter.
    sys.stdout.write("\x1b[?2004h")
    say("Claude Code stand-in " + token)
    report("idle")
    # Started by hand, as herdr's integration would: herdr takes a session once the pane has its agent, and takes no
    # state report after it (so not with the flags, whose tests need the states).
    if "--settings" not in args:
        herdr("report-agent-session", "--source", "herdr:claude", "--agent", "claude", "--agent-session-id", token)
    line, mute, armed = "", False, False
    try:
        while True:
            data = key()
            if "\x03" in data:
                if not line and armed:
                    break
                armed, line = not line, ""
                say("\r\x1b[KPress Ctrl-C again to exit" if armed else "")
                continue
            if "\x04" in data:
                break
            armed = False
            line += data.replace("\x1b", "")
            if "\r" not in line:
                sys.stdout.write(data.replace("\x1b", ""))
                sys.stdout.flush()
                continue
            text, line = line.split("\r", 1)
            say("")
            if text.strip() == "/exit":
                break
            if mute:
                mute = False
            elif text.strip():
                prompt(text.strip(), time.time())
                mute = text.strip() == "mute"
    finally:
        # What it and its hooks wrote goes with it; first, as a hung-up terminal takes no settings. A second hang-up
        # would stop it halfway.
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        if "--settings" in args and os.path.exists(transcript):
            os.remove(transcript)
        for side in re.findall(r"/\.cache/oriel/chat/([0-9a-f-]{36})", settings)[:1]:
            shutil.rmtree(os.path.expanduser("~/.cache/oriel/chat/" + side), ignore_errors=True)
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)


main()
