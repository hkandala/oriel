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


def ui(name, cls="ic"):
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

# session -> workspaces: (name, status, branch, ahead, behind, worktree_child)
SESSIONS = {
    "default": [
        ("oriel", "working", "main", 2, 0, False),
        ("oriel-rex-ui", "", "feat/rex-ui", 5, 1, True),
        ("mira", "done", "main", 0, 0, False),
        ("dotfiles", "idle", "master", 0, 3, False),
        ("infra", "needs", None, 0, 0, False),
    ],
    "pi-herd": [
        ("agents", "working", "main", 0, 0, False),
        ("scratch", "", None, 0, 0, False),
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

# agents on the machine: (agent icon, name, status, session, workspace, tab, age)
AGENTS = [
    ("claude", "claude", "needs", "default", "oriel", "docs", "3m"),
    ("claude", "claude", "needs", "default", "infra", "deploy", "8m"),
    ("pi", "pi", "working", "default", "oriel", "pi", "12m"),
    ("pi", "pi", "working", "pi-herd", "agents", "main", "1m"),
    ("codex", "codex", "done", "default", "mira", "codex", "now"),
    ("opencode", "opencode", "idle", "default", "dotfiles", "1", "2h"),
    ("codex", "codex", "idle", "pi-herd", "agents", "review", "5h"),
]


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


def title_row(sidebar_open, agents_view):
    machine = (f'<span class="pick icononly" title="Machine: This Mac">{ui("laptop")}'
               f'<span class="caret">{ui("chev", "ic xs")}</span></span>')
    workspace = ("" if sidebar_open else
                 f'<span class="pick" title="Workspace">{ui("folder", "ic sm")}<span class="pname">oriel</span>'
                 f'<span class="caret">{ui("chev", "ic xs")}</span></span>')
    return (f'<div class="titlerow">{traffic()}'
            f'<span class="btn{" on" if sidebar_open else ""}" title="Toggle Sidebar ⌃⌘S">{ui("sidebar")}</span>'
            f'<span class="btn{" on" if agents_view else ""}" title="Agents ⌘.">{ui("agents")}'
            f'<span class="ebadge amber"></span></span>'
            f'{machine}{workspace}{tabbar()}<span class="spacer"></span>'
            f'<span class="btn" title="Command Palette ⌘K">{ui("cmd")}</span>'
            f'<span class="btn" title="New Tab ⌘T">{ui("plus")}</span></div>')


# ---------------------------------------------------------------- sidebar
def git_line(branch, ahead, behind):
    if not branch:
        return '<span class="l2 dim">not a git repo</span>'
    counts = ""
    if ahead:
        counts += f' · <span class="ahead">↑{ahead}</span>'
    if behind:
        counts += f' <span class="behind">↓{behind}</span>' if ahead else f' · <span class="behind">↓{behind}</span>'
    return f'<span class="l2"><span class="br">{ui("branch", "ic xs")}</span>{branch}{counts}</span>'


def workspace_rows(session):
    out = []
    for name, status, branch, ahead, behind, child in SESSIONS[session]:
        sel = session == "default" and name == SELECTED_WS
        out.append(f'<div class="ws{" sel" if sel else ""}{" child" if child else ""}">'
                   f'<span class="sicon">{state_icon(status)}</span>'
                   f'<span class="col"><span class="l1">{name}</span>{git_line(branch, ahead, behind)}</span></div>')
    return "".join(out)


def page(session, dots_index):
    dots = "".join(f'<i class="{"on" if i == dots_index else ""}"></i>' for i in range(len(SESSIONS)))
    return (f'<div class="spage"><div class="shead"><span class="sname">{session}</span>'
            f'<span class="splus" title="New Workspace">{ui("plus", "ic xs")}</span></div>'
            f'<div class="list">{workspace_rows(session)}</div><div class="pagedots">{dots}</div></div>')


def footer():
    return (f'<div class="foot"><span class="filter">{ui("filter", "ic xs")} Filter</span>'
            f'<span class="sbtn" title="New Session ⇧⌘N">{ui("plusstack", "ic sm")}</span></div>')


def sidebar_workspaces(swipe=False):
    sessions = list(SESSIONS)
    if swipe:
        pages = f'<div class="pages">{page(sessions[1], 1)}</div>'
    else:
        pages = f'<div class="pages">{page(sessions[0], 0)}</div>'
    return f'<div class="sidebar">{pages}{footer()}</div>'


AGENT_CAP = {"needs": ("Needs you", "amber"), "working": ("Working", "blue"), "done": ("Done", "green"),
             "idle": ("Idle", "gray")}


def agent_row(a, sel=False):
    icon, name, status, session, ws, tab, age = a
    where = f'{session + " · " if session != "default" else ""}{ws} · {tab}'
    label, color = AGENT_CAP[status]
    return (f'<div class="agent{" sel" if sel else ""}">{tile(icon, BADGE.get(status, ""))}'
            f'<span class="col"><span class="l1"><span class="aname">{name}</span>'
            f'<span class="cap {color}">{label}</span></span>'
            f'<span class="l2"><span>{where}</span><span>{age}</span></span></span></div>')


def sidebar_agents():
    order = ["needs", "working", "done", "idle"]
    names = {"needs": "Needs you", "working": "Working", "done": "Done", "idle": "Idle"}
    rows = []
    for st in order:
        group = [a for a in AGENTS if a[2] == st]
        if group:
            rows.append(f'<div class="agroup">{names[st]} <span class="dim">{len(group)}</span></div>')
            rows += [agent_row(a, sel=(a[4], a[5]) == ("oriel", "pi")) for a in group]
    head = (f'<div class="shead"><span class="sname">Agents <span class="dim">· This Mac</span></span>'
            f'<span class="sortpill">{ui("sort", "ic xs")} Priority {ui("chev", "ic xs")}</span></div>')
    return f'<div class="sidebar">{head}<div class="list">{"".join(rows)}</div>{footer()}</div>'


# ---------------------------------------------------------------- strip
def card(icon, title, folder, focused, body, w):
    buttons = "".join(f'<span class="hb">{c}</span>' for c in "◫⊟⤢×") if focused else ""
    return (f'<div class="card{" focused" if focused else ""}" style="flex:{w}">'
            f'<div class="chead">{glyph(icon)}<span class="ttl">{title} <span class="dim">{folder}</span></span>'
            f'<span class="hbs">{buttons}</span></div><pre class="term">{body}</pre></div>')


PI_TEXT = ("π oriel\n\n› Implement phase 10: appearance and interface style\n\n"
           "  • Reading plan/phases/10-appearance.md\n  • Editing Oriel/Views/Style.swift\n\n  ⠋ Working (32s)")
ZSH_TEXT = "hkandala@mbp oriel % git status\nOn branch main\nnothing to commit, working tree clean\nhkandala@mbp oriel % ▌"


def strip(peek=True):
    nxt = '<div class="nextpage"></div>' if peek else ""
    return ('<div class="strip"><div class="page">' + card("pi", "pi", "~/code/oriel", True, PI_TEXT, 1.2)
            + card("zsh", "zsh", "~/code/oriel", False, ZSH_TEXT, 1) + f"</div>{nxt}</div>")


# ---------------------------------------------------------------- popups
def machine_menu():
    rows = [f'<div class="prow{" cur" if cur else ""}"><span class="mi">{ui(icon)}</span>{name}'
            f'{"<span class=kb>" + ui("check", "ic xs") + "</span>" if cur else ""}</div>'
            for name, icon, cur in MACHINES]
    return (f'<div class="popup mach">{"".join(rows)}<div class="psep"></div>'
            f'<div class="prow"><span class="mi">{ui("window")}</span>Open in New Window<span class="kb">⌥ click</span></div>'
            f'<div class="prow"><span class="mi">{ui("plus")}</span>Add Remote Host…</div></div>')


def workspace_menu():
    rows = ['<div class="pfilter">Filter or create…</div>']
    for session, wss in SESSIONS.items():
        rows.append(f'<div class="pg">{session}</div>')
        for name, status, branch, *_rest in wss:
            cur = session == "default" and name == SELECTED_WS
            git = f'<span class="kb">{branch}</span>' if branch else ""
            rows.append(f'<div class="prow{" cur" if cur else ""}"><span class="sicon">{state_icon(status)}</span>'
                        f'{name}{git}</div>')
    rows.append(f'<div class="psep"></div><div class="prow"><span class="mi">{ui("plus")}</span>New Workspace</div>'
                f'<div class="prow"><span class="mi">{ui("plusstack")}</span>New Session<span class="kb">⇧⌘N</span></div>')
    return f'<div class="popup wsm">{"".join(rows)}</div>'


def add_host_sheet():
    icons = ["laptop", "desktop", "server", "cloud", "cpu", "house", "flask", "game"]
    grid = "".join(f'<span class="icell{" on" if i == 2 else ""}">{ui(n)}</span>' for i, n in enumerate(icons))
    return ('<div class="sheet"><div class="stitle">Add Remote Host</div>'
            '<label>Name</label><div class="field">devbox</div>'
            '<label>SSH target</label><div class="field mono">hk@devbox.local</div>'
            f'<label>Icon <span class="dim">· shown in the title row</span></label><div class="igrid">{grid}</div>'
            '<div class="sbtns"><span class="bt">Cancel</span><span class="bt primary">Add</span></div></div>')


# ---------------------------------------------------------------- windows
def window(sidebar=None, popup=None, extra_cls=""):
    side = {"ws": sidebar_workspaces(), "swipe": sidebar_workspaces(True), "agents": sidebar_agents()}.get(sidebar, "")
    return (f'<div class="win {extra_cls}">{title_row(sidebar is not None, sidebar == "agents")}'
            f'<div class="content">{side}{strip()}</div>{popup or ""}</div>')


def two_windows():
    return ('<div class="pair"><div class="mini">' + window("ws") + '<div class="mlabel">Window 1 · This Mac</div></div>'
            '<div class="mini">' + window(None).replace(ui("laptop"), ui("server")) +
            '<div class="mlabel">Window 2 · devbox</div></div></div>')


SCENES = [
    ("A", "Sidebar open: workspaces of one session",
     "Title row, left to right: sidebar toggle, Agents toggle (badge when an agent needs you), the machine "
     "(icon only), then the selected workspace's tabs, always in the title row. The sidebar lists the "
     "workspaces of one herdr session, like herdr: state icon and name, then the git branch with ahead and "
     "behind counts. A worktree workspace sits under its repository. The footer has only the filter and New "
     "Session. Swipe the strip sideways to page through the tabs; swipe the sidebar to change the session.",
     window("ws")),
    ("B", "After a sideways swipe on the sidebar: the next session on this machine",
     "One sidebar page per herdr session that runs on the machine (here default and pi-herd), Arc style, "
     "with page dots; a click on a dot also switches. The page follows the finger during the swipe. The "
     "title row's tabs belong to the selected workspace, so they change when you pick a workspace on this "
     "page.", window("swipe")),
    ("C", "Sidebar collapsed: only the tabs",
     "The same toggle collapses the sidebar. A workspace menu appears next to the machine; the tabs stay in "
     "the title row, and the strip still pages sideways between them.", window(None)),
    ("D", "Sidebar collapsed, workspace menu open",
     "Every workspace of every session on this machine, grouped by session, with its branch. New Workspace "
     "and New Session at the bottom.", window(None, workspace_menu())),
    ("E", "Machine menu open",
     "The machine button shows only the machine's icon. Its menu shows the names. Picking a machine replaces "
     "the window's sessions with that machine's. Add Remote Host lives only here.", window("ws", machine_menu())),
    ("F", "Add Remote Host: the user picks an icon",
     "The icon is how the machine shows in the title row, so the sheet asks for one.",
     window("ws", add_host_sheet())),
    ("G", "Agents view",
     "The Agents toggle turns the sidebar into a list of agents: one row per agent pane, even when a tab "
     "holds several. Sorted by priority (needs you, working, done, idle) or by workspace order. Idle agents "
     "show by default. Each row says where the agent is; a click opens that workspace, tab and pane.",
     window("agents")),
    ("H", "Several windows",
     "Each window shows one machine. Two windows can show different machines, or the same machine (then "
     "they show the same sessions, each with its own selection).", two_windows()),
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
