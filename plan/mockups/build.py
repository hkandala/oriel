"""Builds plan/mockups/layout.html: static mock-ups of Oriel's main window for review.

Run from the repo root: python3 plan/mockups/build.py
Open plan/mockups/layout.html in a browser; add ?scene=A (B, C, ...) to show one scene.
Program icons come from resources/icons (catalog.json + svg/), inlined so the page opens from disk.
"""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICONS = ROOT / "resources/icons"
catalog = {e["id"]: e for e in json.loads((ICONS / "catalog.json").read_text())}

# UI glyphs (simple drawings in the spirit of SF Symbols), 24 x 24, filled.
UI = {
    "sidebar": '<path d="M3 4h18a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zm1 2v12h5V6zm7 0v12h9V6z"/>',
    "agents": '<path d="M9 2.5l1.6 4.4L15 8.5l-4.4 1.6L9 14.5l-1.6-4.4L3 8.5l4.4-1.6zM17.5 12l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9zM4 17h8v2H4zm0 3h11v1.6H4z"/>',
    "laptop": '<path d="M4 5.5A1.5 1.5 0 0 1 5.5 4h13A1.5 1.5 0 0 1 20 5.5V15H4zM6 6v7h12V6zM1.5 16.5h21l-1 2.2a1 1 0 0 1-.9.6H3.4a1 1 0 0 1-.9-.6z"/>',
    "server": '<path d="M4 3h16a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm0 10h16a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1zm2.5-7.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zm0 10a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3z"/>',
    "cloud": '<path d="M7 19a5 5 0 0 1-.6-10A6.5 6.5 0 0 1 19 9.5 4.8 4.8 0 0 1 18.5 19z"/>',
    "desktop": '<path d="M3 4h18a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1h-7v2h3v2H7v-2h3v-2H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zm1 2v9h16V6z"/>',
    "cpu": '<path d="M8 2h2v3h4V2h2v3h2a1 1 0 0 1 1 1v2h3v2h-3v4h3v2h-3v2a1 1 0 0 1-1 1h-2v3h-2v-3h-4v3H8v-3H6a1 1 0 0 1-1-1v-2H2v-2h3v-4H2V8h3V6a1 1 0 0 1 1-1h2zm-1 5v10h10V7zm3 3h4v4h-4z"/>',
    "house": '<path d="M12 3l9 8h-3v9h-5v-6h-2v6H6v-9H3z"/>',
    "flask": '<path d="M8 2h8v2h-1v5.2l5.6 9.8A2 2 0 0 1 18.9 22H5.1a2 2 0 0 1-1.7-3L9 9.2V4H8zm3 2v5.7L8.6 14h6.8L13 9.7V4z"/>',
    "game": '<path d="M7 7h10a5 5 0 0 1 0 10c-1.6 0-2.6-.8-3.4-2h-3.2c-.8 1.2-1.8 2-3.4 2A5 5 0 0 1 7 7zm0 3v1.5H5.5v1.5H7v1.5h1.5V13H10v-1.5H8.5V10zm9 .5a1 1 0 1 0 0 2 1 1 0 0 0 0-2zm2 2a1 1 0 1 0 0 2 1 1 0 0 0 0-2z"/>',
    "plusstack": '<path d="M5 3h14v2H5zM3 7h12v2H5v10h10v-4h2v6H3zm15 0h2v3h3v2h-3v3h-2v-3h-3v-2h3z"/>',
    "branch": '<path d="M6 3a3 3 0 0 1 1 5.8v6.4a3 3 0 1 1-2 0V8.8A3 3 0 0 1 6 3zm12 0a3 3 0 0 1 1 5.8V10a4 4 0 0 1-4 4H8.5v-2H15a2 2 0 0 0 2-2V8.8A3 3 0 0 1 18 3z"/>',
    "filter": '<path d="M3 5h18v2H3zm3 6h12v2H6zm3 6h6v2H9z"/>',
    "plus": '<path d="M11 4h2v7h7v2h-7v7h-2v-7H4v-2h7z"/>',
    "cmd": '<path d="M7 3a4 4 0 0 1 4 4v2h2V7a4 4 0 1 1 4 4h-2v2h2a4 4 0 1 1-4 4v-2h-2v2a4 4 0 1 1-4-4h2v-2H7a4 4 0 0 1 0-8zm0 2a2 2 0 1 0 0 4h2V7a2 2 0 0 0-2-2zm10 0a2 2 0 0 0-2 2v2h2a2 2 0 1 0 0-4zm-6 6v2h2v-2zm-4 4a2 2 0 1 0 2 2v-2zm8 0v2a2 2 0 1 0 2-2z"/>',
    "chev": '<path d="M7 9l5 5 5-5 1.4 1.4L12 16.8l-6.4-6.4z"/>',
    "check": '<path d="M9.5 16.2L5.3 12l-1.4 1.4 5.6 5.6L20.1 8.4 18.7 7z"/>',
    "folder": '<path d="M3 5h7l2 2h9v12H3z"/>',
    "sort": '<path d="M7 4l4 4H8v12H6V8H3zm10 16l-4-4h3V4h2v12h3z"/>',
    "window": '<path d="M3 4h18a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zm1 4v10h16V8z"/>',
}


# Candidate glyphs for the Agents toggle (the user picks one).
UI.update({
    "people": '<path d="M9 4a3.5 3.5 0 1 1 0 7 3.5 3.5 0 0 1 0-7zm7.5 1.5a3 3 0 1 1 0 6 3 3 0 0 1 0-6zM2 19c0-3.3 3.1-6 7-6s7 2.7 7 6v1H2zm15.5-6c2.7.2 4.5 2.4 4.5 5v2h-4.5v-1c0-2.4-1-4.5-2.6-5.8.8-.2 1.7-.2 2.6-.2z"/>',
    "robot": '<path d="M11 2h2v2.1A7 7 0 0 1 19 11v6a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3v-6a7 7 0 0 1 6-6.9zM9 10.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zm6 0a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM8.5 16v1.5h7V16zM2 11h2v5H2zm18 0h2v5h-2z"/>',
    "bubbles": '<path d="M3 4h12a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H8l-4 3v-3H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zm15 4h3a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-1v3l-4-3h-5a1 1 0 0 1-1-1v-1h6a2 2 0 0 0 2-2z"/>',
    "statuslist": '<path d="M5 4.5a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM9 5.5h12v2H9zM5 10a2 2 0 1 1 0 4 2 2 0 0 1 0-4zm4 1h12v2H9zM5 15.5a2 2 0 1 1 0 4 2 2 0 0 1 0-4zm4 1h12v2H9z"/>',
    "pulse": '<path d="M2 11h4.4l2.1-5.6 4.1 12 2.5-6.4H22v2h-5.5l-3.9 10L8.5 11.5 7.8 13H2z"/>',
    "wand": '<path d="M14.6 6.6l2.8 2.8L6.8 20 4 17.2zM17 2l.8 2.2L20 5l-2.2.8L17 8l-.8-2.2L14 5l2.2-.8zM20.5 9l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4-1.4-.6 1.4-.6zM10 2.5l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4L8 4.5l1.4-.6z"/>',
    "stackperson": '<path d="M6 2h12v2H6zM4 5h16v2H4zm-1 3h18a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1zm9 2.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM7.5 19h9c0-2.2-2-3.5-4.5-3.5S7.5 16.8 7.5 19z"/>',
})
UI["sparkles"] = UI["agents"]
# Outline (stroked) glyphs.
UIO = {
    "bubbles": '<path d="M4 4.5h10a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H8.5L5 16v-2.5H4A1.5 1.5 0 0 1 2.5 12V6A1.5 1.5 0 0 1 4 4.5z"/><path d="M15.5 8.5H20A1.5 1.5 0 0 1 21.5 10v6a1.5 1.5 0 0 1-1.5 1.5h-1V20l-3.5-2.5H11a1.5 1.5 0 0 1-1.5-1.5v-2.5"/>',
    "folder": '<path d="M3 6.5A1.5 1.5 0 0 1 4.5 5h4.2l2 2h8.8A1.5 1.5 0 0 1 21 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z"/>',
    "squarestack": '<rect x="7.5" y="3.5" width="13" height="13" rx="2"/><path d="M16.5 20.5h-11a2 2 0 0 1-2-2v-11"/>',
    "rect3": '<rect x="3.5" y="4" width="17" height="6" rx="1.5"/><rect x="3.5" y="14" width="7.5" height="6" rx="1.5"/><rect x="13" y="14" width="7.5" height="6" rx="1.5"/>',
    "tray": '<path d="M3.5 13.5l2.4-7.3A1.5 1.5 0 0 1 7.3 5h9.4a1.5 1.5 0 0 1 1.4 1.2l2.4 7.3v5a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5z"/><path d="M3.5 13.5h5l1 2h5l1-2h5"/>',
    "grid": '<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.5"/>',
    "briefcase": '<rect x="3" y="7" width="18" height="12.5" rx="2"/><path d="M8.5 7V5.5A1.5 1.5 0 0 1 10 4h4a1.5 1.5 0 0 1 1.5 1.5V7M3 12.5h18"/>',
    "cube": '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M4 7.5l8 4.5 8-4.5M12 12v9"/>',
    "sidebarclosed": '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M9 4.5v15"/>',
    "sidebaropen": '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M9 4.5v15"/><path d="M5.6 4.5H9v15H5.6A2.6 2.6 0 0 1 3 16.9V7.1a2.6 2.6 0 0 1 2.6-2.6z" fill="currentColor"/>',
    "bubblesfill": '<path fill="currentColor" d="M4 4.5h10a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H8.5L5 16v-2.5H4A1.5 1.5 0 0 1 2.5 12V6A1.5 1.5 0 0 1 4 4.5z"/><path d="M15.5 8.5H20A1.5 1.5 0 0 1 21.5 10v6a1.5 1.5 0 0 1-1.5 1.5h-1V20l-3.5-2.5H11a1.5 1.5 0 0 1-1.5-1.5v-2.5"/>',
    "sidebarlist": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M5.5 8h1.5M5.5 11h1.5M5.5 14h1.5"/>',
}
AGENT_ICON = "o:bubbles"


def ui(name, cls="ic"):
    if name.startswith("o:"):
        return (f'<svg class="{cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" '
                f'stroke-linecap="round" stroke-linejoin="round">{UIO[name[2:]]}</svg>')
    return f'<svg class="{cls}" viewBox="0 0 24 24" fill="currentColor">{UI[name]}</svg>'


def svg(icon_id):
    raw = re.sub(r"<\?xml[^>]*>", "", (ICONS / catalog[icon_id]["svg"]).read_text())
    return raw.replace("<svg ", '<svg class="g" ', 1)


def tile(icon_id, badge=""):
    t = catalog[icon_id]["tile"]
    dot = f'<span class="badge {badge}"></span>' if badge else ""
    return f'<span class="tile" style="background:{t["background"]};color:{t["glyph"]}">{svg(icon_id)}{dot}</span>'


def stack(ids, badge="", max_n=5):
    ids = ids[:max_n]
    inner = "".join(f'<span class="st" style="left:{4 * (len(ids) - 1 - i)}px;z-index:{10 - i}">'
                    f'{tile(icon_id, badge if i == 0 else "")}</span>' for i, icon_id in enumerate(ids))
    return f'<span class="stack" style="width:{22 + 4 * (len(ids) - 1)}px">{inner}</span>'


def glyph(icon_id):
    return f'<span class="hglyph">{svg(icon_id)}</span>'


DOTS = '<span class="dots"><i></i><i></i><i></i></span>'
BADGE = {"needs": "amber", "done": "green"}


def state_icon(status):
    if status == "working":
        return DOTS
    if status in ("needs", "done"):
        return f'<span class="sdot {BADGE[status]}"></span>'
    if status == "idle":
        return '<span class="sdot idle"></span>'
    return '<span class="sdot none"></span>'


# ---------------------------------------------------------------- sample data
MACHINES = [("This Mac", "laptop", True), ("devbox", "server", False), ("gpu-box", "cpu", False)]
STOPPED = ["orcr-spike-pi", "pi-bench", "swebench-autopilot"]

# session -> workspaces: (name, status, branch, ahead, behind, changed, worktree_child)
SESSIONS = {
    "default": [
        ("oriel", "working", "main", 2, 0, 3, False),
        ("oriel-rex-ui", "", "feat/rex-ui", 5, 1, 12, True),
        ("mira", "done", "main", 0, 0, 0, False),
        ("dotfiles", "idle", "master", 0, 3, 1, False),
        ("infra", "needs", None, 0, 0, 0, False),
    ],
    "pi-herd": [
        ("agents", "working", "main", 0, 0, 0, False),
        ("scratch", "", None, 0, 0, 0, False),
    ],
}
SELECTED_WS = "oriel"

# tabs of the selected workspace: (title, folder, icons, status)
TABS = [
    ("pi", "oriel", ["pi", "zsh"], "working"),
    ("zsh", "~/code/oriel", ["zsh"], ""),
    ("claude", "docs", ["claude"], "needs"),
    ("vim", "README.md", ["vim"], ""),
    ("node", "api", ["node"], ""),
]
SELECTED_TAB = 0

# agents by session: (agent icon, name, status, workspace, tab, age)
AGENTS = {
    "default": [
        ("claude", "claude", "needs", "oriel", "docs", "3m"),
        ("claude", "claude", "needs", "infra", "deploy", "8m"),
        ("pi", "pi", "working", "oriel", "pi", "12m"),
        ("codex", "codex", "done", "mira", "codex", "now"),
        ("opencode", "opencode", "idle", "dotfiles", "1", "2h"),
        ("pi", "pi", "idle", "oriel-rex-ui", "review", "4h"),
    ],
    "pi-herd": [
        ("pi", "pi", "working", "agents", "main", "1m"),
        ("codex", "codex", "idle", "agents", "review", "5h"),
    ],
}


# ---------------------------------------------------------------- title row
def traffic():
    return '<span class="tl"><i class="r"></i><i class="y"></i><i class="g"></i></span>'


def tabbar():
    caps = []
    for i, (title, folder, icons, status) in enumerate(TABS):
        sel = i == SELECTED_TAB
        if i > 0:
            quiet = sel or i - 1 == SELECTED_TAB
            caps.append(f'<span class="sep{" off" if quiet else ""}"></span>')
        slot = '<span class="x">×</span>' if sel else (DOTS if status == "working" else "")
        caps.append(f'<span class="cap-tab{" sel" if sel else ""}">{stack(icons, BADGE.get(status, ""))}'
                    f'<span class="ttl">{title} <span class="dim">{folder}</span></span>{slot}</span>')
    return f'<span class="track">{"".join(caps)}</span>'


def agents_button(on, icon=None):
    glyph_name = icon or ("o:bubblesfill" if on else AGENT_ICON)
    return (f'<span class="btn" title="Agents ⌘.">{ui(glyph_name)}'
            f'<span class="ebadge amber"></span></span>')


def ws_label(session, name, style):
    sep = '<span class="psep2">·</span>' if style == "dot" else '<span class="pbar"></span>'
    return f'<span class="dim">{session}</span>{sep}<span>{name}</span>'


def title_row(sidebar_open, agents_view, machine_icon="laptop", session="default", style="line", ws_icon="o:folder"):
    machine = (f'<span class="pick icononly" title="Machine (⌥-click: open in a new window)">{ui(machine_icon)}'
               f'<span class="caret">{ui("chev", "ic xs")}</span></span>')
    workspace = ("" if sidebar_open else
                 f'<span class="pick" title="Workspace">{ui(ws_icon)}'
                 f'<span class="pname">{ws_label(session, "oriel", style)}</span>'
                 f'<span class="caret">{ui("chev", "ic xs")}</span></span>')
    return (f'<div class="titlerow">{traffic()}'
            f'<span class="btn" title="Toggle Sidebar ⌃⌘S">{ui("o:sidebaropen" if sidebar_open else "o:sidebarclosed")}</span>'
            f'{machine}{workspace}{tabbar()}<span class="spacer"></span>{agents_button(agents_view)}'
            f'<span class="btn" title="Command Palette ⌘K">{ui("cmd")}</span>'
            f'<span class="btn" title="New Tab ⌘T">{ui("plus")}</span></div>')


# ---------------------------------------------------------------- sidebar
def git_line(branch, ahead, behind, changed):
    parts = [f'<span class="br">{ui("branch", "ic xs")}</span>{branch}']
    counts = " ".join(x for x in [f'<span class="ahead">↑{ahead}</span>' if ahead else "",
                                  f'<span class="behind">↓{behind}</span>' if behind else ""] if x)
    if counts:
        parts.append(counts)
    return f'<span class="l2">{" · ".join(parts)}</span>'


def workspace_rows(session):
    out = []
    for name, status, branch, ahead, behind, changed, child in SESSIONS[session]:
        sel = session == "default" and name == SELECTED_WS
        second = git_line(branch, ahead, behind, changed) if branch else ""
        out.append(f'<div class="ws{" sel" if sel else ""}{" child" if child else ""}{"" if branch else " one"}">'
                   f'<span class="sicon">{state_icon(status)}</span>'
                   f'<span class="col"><span class="l1">{name}</span>{second}</span></div>')
    return "".join(out)


def dots(index):
    return "".join(f'<i class="{"on" if i == index else ""}"></i>' for i in range(len(SESSIONS)))


def page(session):
    index = list(SESSIONS).index(session)
    return (f'<div class="spage"><div class="shead"><span class="sname">{session}</span>'
            f'<span class="splus" title="New Workspace">{ui("plus", "ic xs")}</span></div>'
            f'<div class="list">{workspace_rows(session)}</div><div class="pagedots">{dots(index)}</div></div>')


def footer():
    return (f'<div class="foot"><span class="filter">{ui("filter", "ic xs")} Filter</span>'
            f'<span class="sbtn" title="New or Open Session… ⇧⌘N">{ui("plusstack", "ic sm")}</span></div>')


def sidebar_workspaces(session="default"):
    return f'<div class="sidebar"><div class="pages">{page(session)}</div>{footer()}</div>'


AGENT_CAP = {"needs": ("Needs you", "amber"), "working": ("Working", "blue"), "done": ("Done", "green"),
             "idle": ("Idle", "gray")}


def agent_row(a, sel=False):
    icon, name, status, ws, tab, age = a
    label, color = AGENT_CAP[status]
    return (f'<div class="agent{" sel" if sel else ""}">{tile(icon, BADGE.get(status, ""))}'
            f'<span class="col"><span class="l1"><span class="aname">{name}</span>'
            f'<span class="cap {color}">{label}</span></span>'
            f'<span class="l2"><span>{ws} · {tab}</span><span>{age}</span></span></span></div>')


def sidebar_agents(session="default"):
    names = {"needs": "Needs you", "working": "Working", "done": "Done", "idle": "Idle"}
    rows = []
    for st in ["needs", "working", "done", "idle"]:
        group = [a for a in AGENTS[session] if a[2] == st]
        if group:
            rows.append(f'<div class="agroup">{names[st]} <span class="dim">{len(group)}</span></div>')
            rows += [agent_row(a, sel=(a[3], a[4]) == ("oriel", "pi")) for a in group]
    index = list(SESSIONS).index(session)
    head = (f'<div class="shead"><span class="sname">{session} <span class="dim">· agents</span></span>'
            f'<span class="sortpill">{ui("sort", "ic xs")} Priority {ui("chev", "ic xs")}</span></div>')
    return (f'<div class="sidebar"><div class="spage">{head}<div class="list">{"".join(rows)}</div>'
            f'<div class="pagedots">{dots(index)}</div></div>{footer()}</div>')


# ---------------------------------------------------------------- strip
def card(icon, title, folder, focused, body, w):
    buttons = "".join(f'<span class="hb">{c}</span>' for c in "◫⊟⤢×") if focused else ""
    return (f'<div class="card{" focused" if focused else ""}" style="flex:{w}">'
            f'<div class="chead">{glyph(icon)}<span class="ttl">{title} <span class="dim">{folder}</span></span>'
            f'<span class="hbs">{buttons}</span></div><pre class="term">{body}</pre></div>')


PI_TEXT = ("π oriel\n\n› Implement phase 10: appearance and interface style\n\n"
           "  • Reading plan/phases/10-appearance.md\n  • Editing Oriel/Views/Style.swift\n\n  ⠋ Working (32s)")
ZSH_TEXT = "hkandala@mbp oriel % git status\nOn branch main\nnothing to commit, working tree clean\nhkandala@mbp oriel % ▌"


def strip(watching=False):
    banner = ('<div class="watchbar">Controlled in another window <span class="bt primary">Take Back</span></div>'
              if watching else "")
    return (f'<div class="strip{" watching" if watching else ""}"><div class="page">'
            + card("pi", "pi", "~/code/oriel", not watching, PI_TEXT, 1.2)
            + card("zsh", "zsh", "~/code/oriel", False, ZSH_TEXT, 1) + f"</div>{banner}</div>")


# ---------------------------------------------------------------- popups
def machine_menu():
    rows = [f'<div class="prow{" cur" if cur else ""}"><span class="mi">{ui(icon)}</span>{name}'
            f'{"<span class=kb>" + ui("check", "ic xs") + "</span>" if cur else ""}</div>'
            for name, icon, cur in MACHINES]
    return (f'<div class="popup mach">{"".join(rows)}<div class="psep"></div>'
            f'<div class="prow"><span class="mi">{ui("plus")}</span>Add Remote Host…</div></div>')


def workspace_menu():
    rows = ['<div class="pfilter">Filter or create…</div>']
    for session, wss in SESSIONS.items():
        rows.append(f'<div class="pg">{session}</div>')
        for name, status, branch, *_rest in wss:
            cur = session == "default" and name == SELECTED_WS
            git = f'<span class="kb">{branch}</span>' if branch else ""
            rows.append(f'<div class="prow{" cur" if cur else ""}"><span class="sicon">{state_icon(status)}</span>'
                        f'<span class="plabel">{name}</span>{git}</div>')
    rows.append(f'<div class="psep"></div><div class="prow"><span class="mi">{ui("plus")}</span>New Workspace</div>'
                f'<div class="prow"><span class="mi">{ui("plusstack")}</span>New or Open Session…'
                f'<span class="kb">⇧⌘N</span></div>')
    return f'<div class="popup wsm">{"".join(rows)}</div>'


def needs_popover():
    rows = [agent_row(a) for a in AGENTS["default"] if a[2] == "needs"]
    return ('<div class="popup needs"><div class="pg">Needs you <span class="dim">· default</span></div>'
            f'{"".join(rows)}<div class="psep"></div><div class="prow small">Click the button for all agents</div></div>')


def session_sheet():
    running = [s for s in SESSIONS]
    rows = "".join(f'<div class="prow{" cur" if i == 0 else ""}"><span class="mi">{ui("plusstack")}</span>{name}'
                   f'<span class="kb">stopped</span></div>' for i, name in enumerate(STOPPED))
    run = "".join(f'<div class="prow"><span class="mi">{ui("check", "ic xs")}</span>{name}<span class="kb">running</span></div>'
                  for name in running)
    return ('<div class="sheet wide"><div class="stitle">New or Open Session</div>'
            '<div class="field big">pi<span class="caretbar"></span><span class="hint">Type a name, or pick a session below</span></div>'
            f'<div class="slist"><div class="pg">Stopped</div>{rows}<div class="pg">Running</div>{run}</div>'
            '<div class="sbtns"><span class="note">Enter on a stopped session starts it. A new name makes a new session.</span>'
            '<span class="bt">Cancel</span><span class="bt primary">Open</span></div></div>')


# ---------------------------------------------------------------- windows
def window(sidebar=None, popup=None, session="default", machine_icon="laptop", watching=False, agents=False,
           style="line", ws_icon="o:folder"):
    side = ""
    if sidebar == "ws":
        side = sidebar_workspaces(session)
    elif sidebar == "agents":
        side = sidebar_agents(session)
    return (f'<div class="win">{title_row(sidebar is not None, agents or sidebar == "agents", machine_icon, session, style, ws_icon)}'
            f'<div class="content">{side}{strip(watching)}</div>{popup or ""}</div>')


def pair(left, right, l1, l2):
    return (f'<div class="pair"><div class="mini">{left}<div class="mlabel">{l1}</div></div>'
            f'<div class="mini">{right}<div class="mlabel">{l2}</div></div></div>')


SCENES = [
    ("A", "Sidebar open: workspaces of one session",
     "Title row: sidebar toggle (its icon shows the panel filled while the sidebar is open), the machine "
     "(icon only), the selected workspace's tabs (always in the title row), and on the right the Agents button "
     "(outline chat bubbles, amber dot when an agent needs you), \u2318 and +. The sidebar lists the workspaces "
     "of one herdr session, like herdr: state icon and name, then the git branch with ahead and behind counts. "
     "A workspace that is not a git repository shows one line. oriel-rex-ui is a git worktree of oriel, so it "
     "sits under oriel. The footer has the filter and New or Open Session. A sideways swipe on the strip pages "
     "through the tabs; a sideways swipe on the sidebar changes the session.", window("ws")),
    ("B", "After a sideways swipe on the sidebar: the next session on this machine",
     "One sidebar page per running herdr session on the machine (here default and pi-herd), Arc style, with "
     "page dots; a click on a dot also switches.", window("ws", session="pi-herd")),
    ("C", "Sidebar collapsed: only the tabs",
     "A workspace button appears next to the machine: folder icon, then \u201csession | workspace\u201d. The strip "
     "still pages sideways between the tabs.", window(None)),
    ("D", "Workspace menu open",
     "Every workspace of every running session on this machine, grouped under its session, with the branch on "
     "the right. New or Open Session opens the session sheet.", window(None, workspace_menu())),
    ("E", "Machine menu open",
     "Closed, the button shows only the machine's icon; open, the menu shows names. Picking a machine replaces "
     "the window's sessions with that machine's; \u2325-click opens it in a new window instead (not shown in "
     "the menu). Add Remote Host stays a placeholder until remote machines are built.",
     window("ws", machine_menu())),
    ("F", "New or Open Session sheet",
     "The sidebar's New Session button and the workspace menu both open this sheet. Type a new name to make a "
     "session, or pick a stopped session to start it (a running one just switches to its page).",
     window("ws", session_sheet())),
    ("G", "Hover the Agents button: who needs you",
     "Resting the pointer on the chat bubbles shows the agents of this session that need you. A click on one "
     "goes straight to its pane; the sidebar stays as it is. A click on the button itself opens the Agents view.",
     window("ws", needs_popover())),
    ("H", "Agents view: the agents of this session",
     "A click on the Agents button turns the sidebar into a list of the agents of the session on this page "
     "(the first bubble fills while it is on): one row per agent pane, even when a tab holds several. Sorted by "
     "priority (needs you, working, done, idle) or by workspace order. Idle agents show by default. A sideways "
     "swipe shows the next session's agents. A click opens that workspace, tab and pane.", window("agents")),
    ("I", "Two windows, same machine, different sessions",
     "Each window shows one machine and controls the session on its page. Two windows on different sessions "
     "both control their own session.",
     pair(window("ws"), window("ws", session="pi-herd"), "Window 1 \u00b7 This Mac \u00b7 default (controls)",
          "Window 2 \u00b7 This Mac \u00b7 pi-herd (controls)")),
    ("J", "Two windows, same session",
     "When two windows show the same session, the window where you typed last controls it; the other watches "
     "and offers Take Back. Control is per session, not per pane.",
     pair(window("ws"), window("ws", watching=True), "Window 1 \u00b7 default (controls)",
          "Window 2 \u00b7 default (watching)")),
]

CSS = (pathlib.Path(__file__).with_name("layout.css")).read_text()
html = ["<!doctype html><html><head><meta charset='utf-8'><title>Oriel layout mock-ups</title>",
        f"<style>{CSS}</style></head><body><h1>Oriel main window: mock-ups for review</h1>",
        "<p class='lead'>Static mock-ups (dark, Glass). Sample data: This Mac runs two herdr sessions, default "
        "(five workspaces) and pi-herd (two). Built by <code>plan/mockups/build.py</code>; "
        "add <code>?scene=A</code> to the URL for one scene.</p>"]
for letter, name, text, win in SCENES:
    html.append(f"<section data-s='{letter}'><h2>{letter}. {name}</h2><p>{text}</p>{win}</section>")
html.append("<script>const q=new URLSearchParams(location.search).get('scene');"
            "if(q)document.querySelectorAll('section').forEach(s=>{if(s.dataset.s!==q)s.remove()})</script>"
            "</body></html>")
(pathlib.Path(__file__).with_name("layout.html")).write_text("".join(html))
print("wrote plan/mockups/layout.html")
