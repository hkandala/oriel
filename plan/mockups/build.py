"""Builds plan/mockups/layout.html: static mock-ups of Oriel's main window, sidebar shown and hidden.

Run from the repo root: python3 plan/mockups/build.py
Icons come from resources/icons (catalog.json + svg/), inlined so the page opens from disk.
"""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICONS = ROOT / "resources/icons"
catalog = {e["id"]: e for e in json.loads((ICONS / "catalog.json").read_text())}


def svg(icon_id: str) -> str:
    raw = (ICONS / catalog[icon_id]["svg"]).read_text()
    raw = re.sub(r"<\?xml[^>]*>", "", raw)
    return raw.replace("<svg ", '<svg class="g" ', 1)


def tile(icon_id: str, badge: str = "") -> str:
    t = catalog[icon_id]["tile"]
    dot = f'<span class="badge {badge}"></span>' if badge else ""
    return (f'<span class="tile" style="background:{t["background"]};color:{t["glyph"]}">'
            f"{svg(icon_id)}{dot}</span>")


def stack(ids, badge="", max_n=3) -> str:
    ids = ids[:max_n]
    inner = "".join(
        f'<span class="st" style="left:{4 * (len(ids) - 1 - i)}px;z-index:{10 - i}">'
        f'{tile(icon_id, badge if i == 0 else "")}</span>'
        for i, icon_id in enumerate(ids)
    )
    return f'<span class="stack" style="width:{22 + 4 * (len(ids) - 1)}px">{inner}</span>'


def glyph(icon_id: str) -> str:
    return f'<span class="hglyph">{svg(icon_id)}</span>'


DOTS = '<span class="dots"><i></i><i></i><i></i></span>'

# Sample data: (title, folder, icons, status) ; status in "", working, needs, done
WORKSPACES = [
    ("oriel", False, [
        ("pi", "oriel", ["pi", "zsh"], "working"),
        ("zsh", "~/code/oriel", ["zsh"], ""),
        ("claude", "docs", ["claude"], "needs"),
        ("vim", "README.md", ["vim"], ""),
    ]),
    ("mira", False, [
        ("codex", "aai_labs_mira", ["codex"], "done"),
        ("node", "api", ["node", "zsh"], ""),
    ]),
    ("infra", True, [
        ("docker", "compose", ["docker"], ""),
        ("htop", "", ["monitor"], ""),
    ]),
]
SELECTED = ("oriel", 0)


def status_slot(status, selected=False):
    if selected:
        return '<span class="x">×</span>'
    return DOTS if status == "working" else ""


def badge_for(status):
    return {"needs": "amber", "done": "green"}.get(status, "")


def traffic():
    return '<span class="tl"><i class="r"></i><i class="y"></i><i class="g"></i></span>'


def right_buttons(activity_on=False, badge="amber"):
    eye_cls = "btn on" if activity_on else "btn"
    return (f'<span class="{eye_cls}" title="Activity ⌘.">@EYE@<span class="ebadge {badge}"></span></span>'
            '<span class="btn" title="Command Palette ⌘K">⌘</span>'
            '<span class="btn" title="New Tab ⌘T">+</span>')


def sidebar_rows():
    out = []
    for w_index, (name, collapsed, tabs) in enumerate(WORKSPACES):
        needs = sum(1 for t in tabs if t[3] == "needs")
        count = f'<span class="count">{needs}</span>' if collapsed and needs else ""
        chevron = "▸" if collapsed else "▾"
        out.append(f'<div class="wsh"><span class="chev">{chevron}</span>{name}{count}'
                   f'<span class="wplus">+</span></div>')
        if collapsed:
            continue
        for t_index, (title, folder, icons, status) in enumerate(tabs):
            sel = (name, t_index) == SELECTED
            out.append(
                f'<div class="row{" sel" if sel else ""}">{stack(icons, badge_for(status))}'
                f'<span class="ttl">{title} <span class="dim">{folder}</span></span>'
                f'{status_slot(status) if not sel else ""}</div>')
    return "".join(out)


def activity_rows():
    out = []
    caps = {"needs": ("Needs you", "amber"), "done": ("Done", "green"), "working": ("Working", "blue")}
    detail = {"needs": "claude · needs you", "done": "codex · finished", "working": "pi · working"}
    age = {"needs": "3m", "done": "now", "working": "12m"}
    for name, _collapsed, tabs in WORKSPACES:
        rows = [(i, t) for i, t in enumerate(tabs) if t[3] or (name, i) == SELECTED]
        if not rows:
            continue
        out.append(f'<div class="wsh">{name}</div>')
        for t_index, (title, folder, icons, status) in rows:
            sel = (name, t_index) == SELECTED
            label, color = caps.get(status, ("", ""))
            cap = f'<span class="cap {color}">{label}</span>' if label else ""
            out.append(
                f'<div class="row two{" sel" if sel else ""}">{stack(icons, badge_for(status))}'
                f'<span class="col"><span class="l1"><span class="ttl">{title} <span class="dim">{folder}</span>'
                f'</span>{cap}</span><span class="l2"><span>{detail.get(status, "")}</span>'
                f'<span>{age.get(status, "")}</span></span></span></div>')
    return "".join(out)


def sidebar(activity=False):
    body = activity_rows() if activity else sidebar_rows()
    head = ('<div class="mline">Activity <span class="dim">· tabs that need a look</span></div>' if activity
            else '<div class="mline">This Mac</div>')
    foot = ('<div class="foot"><label class="chk"><input type="checkbox"> Show idle agents</label></div>' if activity
            else '<div class="pagedots"><i class="on"></i><i></i></div>'
                 '<div class="foot"><span class="filter">⌕ Filter</span><span class="sbtn">⧉+</span>'
                 '<span class="sbtn">@GLOBE@</span></div>')
    return f'<div class="sidebar">{head}<div class="list">{body}</div>{foot}</div>'


def card(icon, title, folder, focused, body, w):
    buttons = ('<span class="hb">◫</span><span class="hb">⊟</span><span class="hb">⤢</span><span class="hb">×</span>'
               if focused else "")
    return (f'<div class="card{" focused" if focused else ""}" style="flex:{w}">'
            f'<div class="chead">{glyph(icon)}<span class="ttl">{title} <span class="dim">{folder}</span></span>'
            f'<span class="hbs">{buttons}</span></div><pre class="term">{body}</pre></div>')


PI_TEXT = ("π oriel\n\n› Implement phase 10: appearance and interface style\n\n"
           "  • Reading plan/phases/10-appearance.md\n  • Editing Oriel/Views/Style.swift\n\n  ⠋ Working (32s)")
ZSH_TEXT = "hkandala@mbp oriel % git status\nOn branch main\nnothing to commit, working tree clean\nhkandala@mbp oriel % ▌"


def strip():
    return ('<div class="strip">'
            + card("pi", "pi", "~/code/oriel", True, PI_TEXT, 1.2)
            + card("zsh", "zsh", "~/code/oriel", False, ZSH_TEXT, 1)
            + "</div>")


def tabbar():
    name, tabs = WORKSPACES[0][0], WORKSPACES[0][2]
    caps = []
    for i, (title, folder, icons, status) in enumerate(tabs):
        sel = i == SELECTED[1]
        sep = '<span class="sep"></span>' if i > 0 and not sel and i - 1 != SELECTED[1] else '<span class="sep off"></span>' if i > 0 else ""
        caps.append(f'{sep}<span class="cap-tab{" sel" if sel else ""}">{stack(icons, badge_for(status), 5)}'
                    f'<span class="ttl">{title} <span class="dim">{folder}</span></span>'
                    f'{status_slot(status, sel)}</span>')
    return f'<span class="track">{"".join(caps)}</span>'


def place_button(hidden):
    if hidden:
        return ('<span class="place"><span class="pi">@STACK@</span><span class="pname">oriel</span>'
                '<span class="psub">This Mac</span><span class="caret">▾</span></span>')
    return '<span class="place"><span class="pi">@LAP@</span><span class="pname">This Mac</span><span class="caret">▾</span></span>'


def window(sidebar_shown, activity=False, popup=None):
    title = (f'{traffic()}<span class="btn{" on" if sidebar_shown else ""}" title="Toggle Sidebar ⌃⌘S">@SIDEBAR@</span>'
             f'{place_button(not sidebar_shown)}{"" if sidebar_shown else tabbar()}<span class="spacer"></span>'
             f'{right_buttons(activity)}')
    content = (sidebar(activity) if sidebar_shown else "") + strip()
    return (f'<div class="win"><div class="titlerow">{title}</div><div class="content">{content}</div>'
            f'{popup or ""}</div>')


def activity_popup():
    return f'<div class="popup act">{activity_rows()}<div class="foot"><label class="chk"><input type="checkbox"> Show idle agents</label></div></div>'


def picker_popup():
    groups = [
        ("This Mac", "@LAP@", [("oriel", "", True), ("mira", "green", False), ("infra", "", False)]),
        ("This Mac · pi-herd", "@LAP@", [("agents", "amber", False), ("scratch", "", False)]),
        ("devbox", "@GLOBE@", [("api", "", False)]),
    ]
    rows = []
    for gname, icon, wss in groups:
        rows.append(f'<div class="pg">{icon} {gname}</div>')
        for ws, b, cur in wss:
            dot = f'<span class="pdot {b}"></span>' if b else ""
            rows.append(f'<div class="prow{" cur" if cur else ""}"><span>{"✓" if cur else ""}</span>{ws}{dot}</div>')
    rows.append('<div class="psep"></div><div class="prow"><span>⧉</span>New Workspace</div>'
                '<div class="prow"><span>＋</span>New Session…<span class="kb">⇧⌘N</span></div>'
                '<div class="prow"><span>@GLOBE@</span>Add Machine…</div>')
    return f'<div class="popup pick"><div class="pfilter">⌕ Filter or create…</div>{"".join(rows)}</div>'


SCENES = [
    ("A", "Sidebar shown", "The sidebar button (left of the title row) is always there; ⌃⌘S does the same. The sidebar shows one "
     "machine page: herdr's workspaces as sections, their tabs as rows. A collapsed section (infra) shows how many "
     "agents need you. Page dots appear once there is more than one machine. The title-row button shows the "
     "machine.", window(True)),
    ("B", "Sidebar hidden", "The same toggle hides the sidebar; the selected workspace's tabs move into the title row "
     "as capsules on a track. The title-row button now shows the workspace (oriel) and its machine. This is the "
     "proposal in question 1.", window(False)),
    ("C", "Sidebar shown, Activity on (eye)", "The eye filters the sidebar: only tabs whose agents work, need you or "
     "finished and are not seen yet, each with a second line (what happened, how long ago). The tab you are on "
     "stays listed while selected. A seen tab leaves the list when you move to another tab.", window(True, True)),
    ("D", "Sidebar hidden, Activity on", "With the sidebar hidden, the eye opens the same list as a popup under it.",
     window(False, True, activity_popup())),
    ("E", "Sidebar hidden, place button open (proposal)", "One list for every machine and workspace: machines as "
     "groups, workspaces as rows, a dot when something there needs you. Pick a workspace to show its tabs.",
     window(False, False, picker_popup())),
]

ICONS_UI = {'@EYE@': '<svg class="ic" viewBox="0 0 24 24"><path fill="currentColor" d="M12 5C6.5 5 2.7 9.3 1.5 12c1.2 2.7 5 7 10.5 7s9.3-4.3 10.5-7C21.3 9.3 17.5 5 12 5zm0 11.5A4.5 4.5 0 1 1 12 7.5a4.5 4.5 0 0 1 0 9zm0-7a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z"/></svg>', '@GLOBE@': '<svg class="ic" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.9a15.7 15.7 0 0 0-1.4-3.6A8 8 0 0 1 18.9 8zM12 4.1c.8 1.1 1.5 2.4 1.9 3.9h-3.8c.4-1.5 1.1-2.8 1.9-3.9zM4.3 14a8 8 0 0 1 0-4h3.3a16 16 0 0 0 0 4zm.8 2h2.9c.3 1.3.8 2.5 1.4 3.6A8 8 0 0 1 5.1 16zM8 8H5.1a8 8 0 0 1 4.3-3.6C8.8 5.5 8.3 6.7 8 8zm4 11.9c-.8-1.1-1.5-2.4-1.9-3.9h3.8c-.4 1.5-1.1 2.8-1.9 3.9zM14.3 14H9.7a14.7 14.7 0 0 1 0-4h4.6a14.7 14.7 0 0 1 0 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h2.9a8 8 0 0 1-4.3 3.6zm1.8-5.6a16 16 0 0 0 0-4h3.3a8 8 0 0 1 0 4z"/></svg>', '@STACK@': '<svg class="ic" viewBox="0 0 24 24"><path fill="currentColor" d="M5 3h14v2H5zM3 7h18v14H3zm2 2v10h14V9z"/></svg>', '@LAP@': '<svg class="ic" viewBox="0 0 24 24"><path fill="currentColor" d="M4 5.5A1.5 1.5 0 0 1 5.5 4h13A1.5 1.5 0 0 1 20 5.5V15H4zM6 6v7h12V6zM1.5 16.5h21l-1 2.2a1 1 0 0 1-.9.6H3.4a1 1 0 0 1-.9-.6z"/></svg>', '@SIDEBAR@': '<svg class="ic" viewBox="0 0 24 24"><path fill="currentColor" d="M3 4h18a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zm1 2v12h5V6zm7 0v12h9V6z"/></svg>'}

CSS = (pathlib.Path(__file__).with_name("layout.css")).read_text()

html = ["<!doctype html><html><head><meta charset='utf-8'><title>Oriel layout mock-ups</title>",
        f"<style>{CSS}</style></head><body><h1>Oriel main window: sidebar shown and hidden</h1>",
        "<p class='lead'>Static mock-ups for review (dark, Glass). Sample data: one machine (This Mac) with three "
        "workspaces. Built by <code>plan/mockups/build.py</code>.</p>"]
for letter, name, text, win in SCENES:
    html.append(f"<section data-s='{letter}'><h2>{letter}. {name}</h2><p>{text}</p>{win}</section>")
html.append("<script>const q=new URLSearchParams(location.search).get('scene');if(q)document.querySelectorAll('section').forEach(s=>{if(s.dataset.s!==q)s.remove()})</script></body></html>")
page = "".join(html)
for token, markup in ICONS_UI.items():
    page = page.replace(token, markup)
(pathlib.Path(__file__).with_name("layout.html")).write_text(page)
print("wrote plan/mockups/layout.html")
