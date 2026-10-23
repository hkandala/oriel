#!/usr/bin/env python3
"""Build resources/metrics/dashboard.html from plan/metrics/*.json, git and CI runs.

Run from anywhere: python3 resources/metrics/build.py
"""

import glob
import html
import json
import os
import re
import statistics
import subprocess
from collections import defaultdict
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CI_CACHE = os.path.join(HERE, "ci-runs.json")
OUT = os.path.join(HERE, "dashboard.html")

ROLES = {"spec": "Spec", "ponytail": "Ponytail", "e2e": "E2E / visual", "visual": "E2E / visual",
         "verifier": "Verifier", "docs helper": "Docs helper"}
ROLE_ORDER = ["Spec", "Ponytail", "E2E / visual", "Verifier", "Self-review", "Docs helper"]
ROLE_COLOR = {"Spec": "#4f7cff", "Ponytail": "#e0a020", "E2E / visual": "#2fb07a", "Verifier": "#c05ad0",
              "Self-review": "#8a8f98", "Docs helper": "#e06050"}


def git(*args):
    r = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def when(s):
    try:
        return datetime.fromisoformat(s)
    except (TypeError, ValueError):
        return None


def minutes(a, b):
    a, b = when(a), when(b)
    return round((b - a).total_seconds() / 60) if a and b else None


def num(x):
    return x if isinstance(x, (int, float)) and not isinstance(x, bool) else None


def hm(m):
    return "—" if m is None else f"{int(m) // 60}h{int(m) % 60:02d}"


def esc(x):
    return html.escape(str(x))


# ---------- inputs ----------

def load_items():
    """One item per phase run; a phase's follow_up becomes its own item."""
    items = []
    for path in glob.glob(os.path.join(ROOT, "plan/metrics/*.json")):
        d = json.load(open(path))
        reviews = list(d.get("reviews", []))
        if isinstance(d.get("verifier"), dict):  # later phases record the verifier outside reviews
            reviews.append({"role": "verifier", "round": None, **d["verifier"]})
        items.append({**d, "label": str(d.get("phase", os.path.basename(path)[:-5])), "reviews": reviews})
        fu = d.get("follow_up")
        if isinstance(fu, dict):
            items.append({**fu, "phase": d.get("phase"), "label": f"{d.get('phase')}b follow-up",
                          "agent": d.get("agent", ""), "review_rounds": len(fu.get("reviews", [])),
                          "reviews": list(fu.get("reviews", []))})
    for it in items:
        it["minutes"] = minutes(it.get("started"), it.get("finished"))
        for r in it["reviews"]:
            r["minutes"] = num(r.get("minutes")) if num(r.get("minutes")) is not None else \
                minutes(r.get("started"), r.get("finished"))
    return sorted(items, key=lambda i: (not isinstance(i.get("phase"), int), i.get("phase") if isinstance(
        i.get("phase"), int) else 0, when(i.get("started")) or datetime.max.astimezone()))


def progress_log_gui():
    """GUI-lock minutes from plan/execution.md's Progress log for phases whose json lacks them."""
    out = {}
    text = open(os.path.join(ROOT, "plan/execution.md")).read()
    for m in re.finditer(r"^\| (\w+) \|[^|\n]*\|[^|\n]*\|([^|\n]*)\|", text, re.M):
        g = re.search(r"~(\d+) min GUI lock", m.group(2))
        if g:
            out[m.group(1)] = int(g.group(1))
    return out


def gui_minutes(it, log):
    if num(it.get("gui_lock_minutes")) is not None:
        return it["gui_lock_minutes"]
    if isinstance(it.get("gui_runs"), dict) and num(it["gui_runs"].get("total_lock_minutes")) is not None:
        return it["gui_runs"]["total_lock_minutes"]
    return None if "follow-up" in it["label"] else log.get(it["label"])


def shortstat(rng):
    out = git("diff", "--shortstat", rng)
    n = [int(re.search(rf"(\d+) {w}", out).group(1)) if re.search(rf"(\d+) {w}", out) else 0
         for w in ("file", "insertion", "deletion")]
    return {"files": n[0], "add": n[1], "del": n[2]}


def git_stats(items):
    """Commits in each phase's base..head and its net diff; totals from the first base to the last head."""
    for it in items:
        rng = f"{it.get('base')}..{it.get('head')}"
        it["shas"] = git("rev-list", rng).split()
        it["git"] = {"commits": len(it["shas"]), **shortstat(rng)}
    timed = [i for i in items if when(i.get("started")) and when(i.get("finished"))]
    first = min(timed, key=lambda i: when(i["started"]))
    last = max(timed, key=lambda i: when(i["finished"]))
    return shortstat(f"{first.get('base')}..{last.get('head')}")


def ci_runs():
    r = subprocess.run(["gh", "run", "list", "--limit", "1000", "--json",
                        "databaseId,createdAt,startedAt,updatedAt,conclusion,event,headSha,workflowName,status"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip().startswith("["):
        runs = json.loads(r.stdout)
        with open(CI_CACHE, "w") as f:
            json.dump(runs, f, indent=0)
        return runs
    return json.load(open(CI_CACHE)) if os.path.exists(CI_CACHE) else []


def ci_per_item(items, runs):
    """A run belongs to a phase when its commit is in the phase's base..head (parallel phases share runs)."""
    runs = [r for r in runs if r.get("workflowName") == "ci"]
    for it in items:
        shas = set(it["shas"])
        mine = [r for r in runs if r.get("headSha") in shas]
        it["ci"] = mine


def ci_summary(runs):
    by = defaultdict(int)
    for r in runs:
        by[r.get("conclusion") or r.get("status")] += 1
    mins = [minutes(r.get("startedAt", "").replace("Z", "+00:00"), r.get("updatedAt", "").replace("Z", "+00:00"))
            for r in runs]
    return {"n": len(runs), "ok": by["success"], "fail": by["failure"], "cancel": by["cancelled"],
            "min": sum(m for m in mins if m)}


# ---------- numbers ----------

def role_stats(items):
    rows = defaultdict(list)
    for it in items:
        for r in it["reviews"]:
            rows[ROLES.get(r.get("role"), str(r.get("role")).capitalize())].append(r)
    out = []
    for name in ROLE_ORDER + sorted(set(rows) - set(ROLE_ORDER)):
        if name == "Self-review":
            f = [num(it.get("self_review_findings")) for it in items]
            f = [x for x in f if x is not None]
            out.append({"role": name, "count": len(f), "findings_total": sum(f), "self": True})
            continue
        rs = rows.get(name)
        if not rs:
            continue
        out.append(summarize(name, rs))
    return out


def summarize(name, rs):
    mins = [r["minutes"] for r in rs if r["minutes"] is not None]
    scored = [r for r in rs if num(r.get("value")) is not None]
    sev = defaultdict(int)
    for r in rs:
        for k, v in (r.get("findings") or {}).items():
            sev[k] += num(v) or 0
    gen = sum(num(r.get("genuine")) or 0 for r in rs)
    rej = sum(num(r.get("rejected")) or 0 for r in rs)
    scored_min = sum(r["minutes"] or 0 for r in scored)

    def part(sub):
        sc = [r for r in sub if num(r.get("value")) is not None]
        return {"count": len(sub), "mean": mean([r["value"] for r in sc]),
                "high": share([r["value"] >= 4 for r in sc]),
                "genuine": sum(num(r.get("genuine")) or 0 for r in sub)}

    return {
        "role": name, "count": len(rs), "total_min": sum(mins), "median_min": median(mins),
        "sev": sev, "genuine": gen, "rejected": rej, "genuine_share": gen / (gen + rej) if gen + rej else None,
        "mean": mean([r["value"] for r in scored]), "high": share([r["value"] >= 4 for r in scored]),
        "value_per_10": sum(r["value"] for r in scored) / scored_min * 10 if scored_min else None,
        "genuine_per_10": gen / sum(mins) * 10 if sum(mins) else None,
        "r1": part([r for r in rs if r.get("round") == 1]),
        "later": part([r for r in rs if num(r.get("round")) and r["round"] > 1]),
        "notes": [r for r in scored if r["value"] >= 4 and r.get("note")],
        "low_notes": [r for r in scored if r["value"] <= 1 and r.get("note")],
    }


def mean(xs):
    return sum(xs) / len(xs) if xs else None


def median(xs):
    return statistics.median(xs) if xs else None


def share(bs):
    return sum(bs) / len(bs) if bs else None


def verdict(s):
    if s.get("self") or s["high"] is None:
        return ("—", "no value scores recorded")
    if s["count"] < 3:
        return ("Too few runs", f"only {s['count']} run")
    if (s["r1"]["high"] or 0) >= 0.5 > (s["later"]["high"] or 0):
        return ("Must in round 1", "value 4–5 in most round-1 runs, rarely later")
    if s["high"] >= 0.5:
        return ("Must", "value 4–5 in at least half its runs")
    if (s["median_min"] or 99) <= 3 and (s["genuine_share"] or 0) >= 0.6:
        return ("Cheap, keep", "low value but takes minutes and most findings stick")
    return ("Adds little", "value 4–5 in under half its runs")


# ---------- html ----------

def pct(x):
    return "—" if x is None else f"{x * 100:.0f}%"


def f1(x):
    return "—" if x is None else f"{x:.1f}"


def bar_chart(rows, unit, width=640):
    """rows: [(label, value, text)] -> horizontal bar SVG."""
    rows = [r for r in rows if r[1] is not None]
    top = max([r[1] for r in rows] + [1])
    h, lw = 22, 110
    out = [f'<svg viewBox="0 0 {width} {len(rows) * h + 6}" class="chart" role="img" aria-label="{esc(unit)}">']
    for i, (label, v, text) in enumerate(rows):
        y = i * h + 3
        w = (width - lw - 70) * v / top
        out.append(f'<text x="{lw - 8}" y="{y + 15}" text-anchor="end" class="lbl">{esc(label)}</text>'
                   f'<rect x="{lw}" y="{y + 3}" width="{w:.1f}" height="{h - 8}" rx="3" class="bar"/>'
                   f'<text x="{lw + w + 6:.1f}" y="{y + 15}" class="val">{esc(text)}</text>')
    out.append("</svg>")
    return "".join(out)


def timeline(items, width=980):
    spans = [(it, when(it.get("started")), when(it.get("finished"))) for it in items]
    spans = [s for s in spans if s[1] and s[2]]
    if not spans:
        return ""
    t0, t1 = min(s[1] for s in spans), max(s[2] for s in spans)
    tz = spans[0][1].tzinfo
    lanes, lane_of = [], {}
    for it, a, b in sorted(spans, key=lambda s: s[1]):  # greedy: first lane free at the phase's start
        for i, end in enumerate(lanes):
            if end <= a:
                lanes[i] = b
                lane_of[id(it)] = i
                break
        else:
            lanes.append(b)
            lane_of[id(it)] = len(lanes) - 1
    lw, lh, top = 10, 46, 24
    span = (t1 - t0).total_seconds() or 1

    def x(t):
        return lw + (width - lw - 10) * (t - t0).total_seconds() / span

    out = [f'<svg viewBox="0 0 {width} {top + len(lanes) * lh + 8}" class="chart" role="img" '
           'aria-label="Timeline of phases">']
    hour = t0.astimezone(tz).replace(minute=0, second=0, microsecond=0)
    step = 2 if span > 12 * 3600 else 1
    while hour <= t1:
        if hour >= t0:
            out.append(f'<line x1="{x(hour):.1f}" x2="{x(hour):.1f}" y1="{top - 4}" '
                       f'y2="{top + len(lanes) * lh}" class="grid"/>'
                       f'<text x="{x(hour):.1f}" y="{top - 8}" text-anchor="middle" class="tick">'
                       f'{hour.strftime("%a %H:%M") if hour.hour in (0, 1) or hour == t0 else hour.strftime("%H:%M")}'
                       '</text>')
        hour = hour.fromtimestamp(hour.timestamp() + 3600 * step, tz)
    for it, a, b in spans:
        y = top + lane_of[id(it)] * lh + 4
        tip = f"Phase {it['label']}: {a.strftime('%a %H:%M')}–{b.strftime('%H:%M')} ({hm(it['minutes'])})"
        out.append(f'<g><title>{esc(tip)}</title><rect x="{x(a):.1f}" y="{y}" width="{max(x(b) - x(a), 2):.1f}" '
                   f'height="22" rx="4" class="phase"/>'
                   f'<text x="{x(a) + 5:.1f}" y="{y + 15}" class="plbl">{esc(it["label"].split()[0])}</text></g>')
        for r in it["reviews"]:
            ra, rb = when(r.get("started")), when(r.get("finished"))
            if ra and rb:
                role = ROLES.get(r.get("role"), "Docs helper")
                out.append(f'<rect x="{x(ra):.1f}" y="{y + 25}" width="{max(x(rb) - x(ra), 1.5):.1f}" height="8" '
                           f'fill="{ROLE_COLOR.get(role, "#888")}" opacity=".85"><title>{esc(r.get("name", role))}: '
                           f'{r["minutes"]} min</title></rect>')
    out.append("</svg>")
    legend = "".join(f'<span><i style="background:{ROLE_COLOR[r]}"></i>{r}</span>'
                     for r in ROLE_ORDER if r != "Self-review")
    return "".join(out) + f'<p class="legend">Thin bars under a phase are its review agents: {legend}</p>'


CSS = """
:root{--bg:#fafafa;--fg:#1d1d1f;--mut:#6e6e73;--card:#fff;--line:#e3e3e8;--bar:#4f7cff;--ph:#c9d6ff;--phf:#1d2b5a}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#f2f2f4;--mut:#9a9aa2;--card:#1f1f22;--line:#333338;
--bar:#6f93ff;--ph:#2c3a6b;--phf:#dfe6ff}}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;
background:var(--bg);color:var(--fg)}main{max-width:1060px;margin:0 auto;padding:28px 20px 60px}
h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:34px 0 10px}p.sub,.mut{color:var(--mut)}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.card b{display:block;font-size:22px;font-variant-numeric:tabular-nums}.card span{color:var(--mut);font-size:12px}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:10px;
overflow:hidden;font-variant-numeric:tabular-nums}th,td{padding:6px 8px;border-bottom:1px solid var(--line);
text-align:right;white-space:nowrap}td.l{white-space:normal}th{font-size:12px;color:var(--mut);font-weight:600}
td:first-child,th:first-child,td.l,th.l{text-align:left}tr:last-child td{border-bottom:0}
.wrap{overflow-x:auto}.chart{width:100%;height:auto;background:var(--card);border:1px solid var(--line);
border-radius:10px}.lbl,.val,.tick,.plbl{font-size:12px;fill:var(--fg)}.tick{fill:var(--mut);font-size:10px}
.bar{fill:var(--bar)}.grid{stroke:var(--line)}.phase{fill:var(--ph)}.plbl{fill:var(--phf);font-weight:600}
.two{display:grid;grid-template-columns:1fr 1fr;gap:14px}@media (max-width:800px){.two{grid-template-columns:1fr}}
.legend span{margin-right:12px;white-space:nowrap}.legend i{display:inline-block;width:10px;height:10px;
border-radius:2px;margin-right:4px}.pill{white-space:nowrap;padding:2px 8px;border-radius:99px;font-size:12px;font-weight:600}
.Must{background:#2fb07a33;color:#1f9a63}.Mustinround1{background:#4f7cff33;color:#4f7cff}
.Cheapkeep{background:#e0a02033;color:#b07a00}.Addslittle{background:#e0605033;color:#d04a3a}
details{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:8px 14px;margin:8px 0}
summary{cursor:pointer;font-weight:600}li{margin:4px 0}.ok{color:#2fb07a}.bad{color:#e06050}
"""


def files(i):
    own = i.get("files_changed_excluding_generated_icons")
    return f"<span title='{own} without generated icons'>{i['git']['files']}*</span>" if own else i["git"]["files"]


def page(items, total, roles):
    log_gui = progress_log_gui()
    for it in items:
        it["gui"] = gui_minutes(it, log_gui)
    spans = [(when(i.get("started")), when(i.get("finished"))) for i in items]
    spans = [s for s in spans if all(s)]
    elapsed = (max(b for _, b in spans) - min(a for a, _ in spans)).total_seconds() / 60 if spans else None
    agent_min = sum(i["minutes"] or 0 for i in items)
    all_shas = set().union(*[set(i["shas"]) for i in items])
    n_reviews = sum(len(i["reviews"]) for i in items)
    rounds = sum(num(i.get("review_rounds")) or 0 for i in items)
    gui = [i["gui"] for i in items if i["gui"] is not None]
    ci_ids = {r["databaseId"]: r for i in items for r in i["ci"]}
    ci = ci_summary(list(ci_ids.values()))
    phases = [i for i in items if "follow-up" not in i["label"]]
    first, last = phases[0]["label"] if phases else "", phases[-1]["label"] if phases else ""

    cards = [
        (hm(elapsed), "elapsed, first start to last finish"),
        (hm(agent_min), f"phase-agent time, summed ({len(items)} runs)"),
        (len(all_shas), "commits on main in the phase ranges"),
        (f"+{total['add']:,} / −{total['del']:,}", f"net lines added / removed in {total['files']} files"),
        (n_reviews, "review agents started"),
        (rounds, "review rounds"),
        (f"{sum(gui)} min", f"GUI lock (known for {len(gui)} of {len(items)})"),
        (ci["n"], f"CI runs: {ci['ok']} green, {ci['fail']} failed, {ci['cancel']} cancelled"),
        (hm(ci["min"]), "CI runner time"),
    ]
    h = [f"<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content='width=device-width'>"
         f"<title>Oriel UI polish: metrics</title><style>{CSS}</style><main>"
         f"<h1>Oriel UI polish: how the phases went</h1><p class=sub>Phases {esc(first)}–{esc(last)}, "
         f"built from plan/metrics/*.json, git and GitHub Actions. Generated {datetime.now():%Y-%m-%d %H:%M}.</p>"
         "<h2>Totals</h2><div class=cards>"]
    h += [f"<div class=card><b>{esc(v)}</b><span>{esc(t)}</span></div>" for v, t in cards]
    h.append("</div>")

    # per phase table
    h.append("<h2>Each phase</h2><div class=wrap><table><tr><th>Phase</th><th class=l>Agent</th><th>Time</th>"
             "<th title='As the phase agent recorded / all commits in base..head on main'>Commits<br>own / range</th>"
             "<th>Files</th><th>Lines +</th><th>Lines −</th><th>Rounds</th><th>Reviewers</th><th>E2E runs</th>"
             "<th>GUI min</th><th title='ci workflow runs on commits in the range'>CI runs</th><th>CI green</th></tr>")
    for i in items:
        e2e = i.get("e2e_runs")
        e2e = f"<span title='{esc(e2e)}'>hand</span>" if isinstance(e2e, str) else esc(num(e2e) or "—")
        c = ci_summary(i["ci"])
        green = i.get("ci_green")
        green = "<span class=ok>yes</span>" if green is True else "<span class=bad>no</span>" if green is False else "—"
        h.append(f"<tr><td>{esc(i['label'])}</td><td class=l>{esc(re.sub(r" ?[(].*", "", i.get('agent', '')))}</td><td>{hm(i['minutes'])}</td>"
                 f"<td>{esc(num(i.get('commits')) or '—')} / {i['git']['commits']}</td><td>{files(i)}</td>"
                 f"<td>{i['git']['add']:,}</td><td>{i['git']['del']:,}</td><td>{esc(num(i.get('review_rounds')) or '—')}</td>"
                 f"<td>{len(i['reviews'])}</td><td>{e2e}</td><td>{esc(i['gui'] if i['gui'] is not None else '—')}</td>"
                 f"<td title='{c['ok']} green, {c['fail']} failed, {c['cancel']} cancelled'>{c['n']}"
                 f"{' <span class=bad>(%d failed)</span>' % c['fail'] if c['fail'] else ''}</td>"
                 f"<td>{green}</td></tr>")
    h.append("</table></div><p class=mut>Files and lines are the net git diff of the phase's base..head (* includes "
             "generated files; hover for the count without them). Phases that ran "
             "side by side (see the timeline) share commits and CI runs in their ranges, so the range columns "
             "overlap; the totals above count each commit and run once. GUI minutes come from the json or the "
             "Progress log in plan/execution.md.</p>")

    h.append("<div class=two><div><h2>Time per phase</h2>"
             + bar_chart([(i["label"], i["minutes"], hm(i["minutes"])) for i in items], "Time per phase")
             + "</div><div><h2>Commits per phase (recorded)</h2>"
             + bar_chart([(i["label"], num(i.get("commits")), str(num(i.get("commits")))) for i in items],
                         "Commits per phase") + "</div></div>")

    h.append("<h2>Timeline</h2>" + timeline(items))

    # roles
    h.append("<h2>Each reviewer role</h2><div class=wrap><table><tr><th>Role</th><th>Runs</th><th>Total min</th>"
             "<th>Median min</th><th>Findings<br>blocker / should / nit</th><th>Genuine</th><th>Rejected</th>"
             "<th>Mean value<br>(1–5)</th><th>Round 1<br>runs · mean · 4–5</th>"
             "<th>Later rounds<br>runs · mean · 4–5</th></tr>")
    for s in roles:
        if s.get("self"):
            h.append(f"<tr><td>{s['role']}</td><td>{s['count']}</td><td colspan=3 class=l>by the phase agent, no time "
                     f"recorded</td><td colspan=5 class=l>{s['findings_total']} findings in total, "
                     f"{s['findings_total'] / max(s['count'], 1):.1f} per phase</td></tr>")
            continue
        h.append(f"<tr><td>{s['role']}</td><td>{s['count']}</td><td>{s['total_min']}</td><td>{f1(s['median_min'])}</td>"
                 f"<td>{s['sev']['blocker']} / {s['sev']['should']} / {s['sev']['nit']}</td>"
                 f"<td>{s['genuine']}</td><td>{s['rejected']}</td><td>{f1(s['mean'])}</td>"
                 f"<td>{s['r1']['count']} · {f1(s['r1']['mean'])} · {pct(s['r1']['high'])}</td>"
                 f"<td>{s['later']['count']} · {f1(s['later']['mean'])} · {pct(s['later']['high'])}</td></tr>")
    h.append("</table></div><p class=mut>Value is the phase agent's own score: 1 = nothing new, 5 = caught a real bug "
             "nothing else caught. Genuine = led to a change; rejected = wrong, duplicate or not worth it. The "
             "verifier in phases 20 onward has a time and a verdict but no findings or score.</p>")
    h.append("<div class=two><div><h2>Minutes per role</h2>"
             + bar_chart([(s["role"], s.get("total_min"), f"{s.get('total_min')} min") for s in roles
                          if not s.get("self")], "Minutes per role")
             + "</div><div><h2>Genuine findings per role</h2>"
             + bar_chart([(s["role"], s.get("genuine"), str(s.get("genuine"))) for s in roles if not s.get("self")],
                         "Genuine findings per role") + "</div></div>")

    # must
    h.append("<h2>Which reviews are a must</h2><div class=wrap><table><tr><th>Role</th><th class=l>Verdict</th>"
             "<th>Runs with value 4–5</th><th>Findings that stuck</th><th>Value points per 10 min</th>"
             "<th>Genuine findings per 10 min</th><th class=l>Why</th></tr>")
    for s in roles:
        if s.get("self"):
            continue
        v, why = verdict(s)
        h.append(f"<tr><td>{s['role']}</td><td class=l><span class='pill {v.replace(' ', '').replace(',', '')}'>"
                 f"{v}</span></td><td>{pct(s['high'])}</td><td>{pct(s['genuine_share'])}</td>"
                 f"<td>{f1(s['value_per_10'])}</td><td>{f1(s['genuine_per_10'])}</td><td class=l>{why}</td></tr>")
    h.append("</table></div><p class=mut>Rule (3+ runs): Must in round 1 = value 4–5 in at least half its round-1 "
             "runs but under half later; Must = value 4–5 in at least half its runs; Cheap, keep = median ≤3 min and ≥60% of findings stick; else Adds little. Value per "
             "minute favors quick reviews, so read it next to the share of 4–5 runs.</p>")
    for s in roles:
        if s.get("self") or not (s["notes"] or s["low_notes"]):
            continue
        h.append(f"<details><summary>{s['role']}: what it caught ({len(s['notes'])} runs scored 4–5, "
                 f"{len(s['low_notes'])} scored 1)</summary><ul>")
        h += [f"<li><b>{esc(r.get('name', ''))}</b> ({r['value']}, {r['minutes']} min): {esc(r['note'])}</li>"
              for r in s["notes"]]
        h += [f"<li class=mut><b>{esc(r.get('name', ''))}</b> (1, {r['minutes']} min): {esc(r['note'])}</li>"
              for r in s["low_notes"]]
        h.append("</ul></details>")

    h.append("<h2>What the phase agents said</h2>")
    for i in items:
        notes = [i.get("notes")] + list(i.get("lessons") or [])
        if isinstance(i.get("verifier"), dict) and i["verifier"].get("verdict"):
            notes.append("Verifier: " + i["verifier"]["verdict"])
        notes = [n for n in notes if n]
        if notes:
            h.append(f"<details><summary>Phase {esc(i['label'])}</summary><ul>"
                     + "".join(f"<li>{esc(n)}</li>" for n in notes) + "</ul></details>")
    h.append("</main></html>\n")
    return "".join(h)


def main():
    items = load_items()
    total = git_stats(items)
    ci_per_item(items, ci_runs())
    with open(OUT, "w") as f:
        f.write(page(items, total, role_stats(items)))
    print(OUT)


if __name__ == "__main__":
    main()
