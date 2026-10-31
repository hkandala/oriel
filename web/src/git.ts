// The Git card's home (Oriel/Plugins/Git): the commit message and Commit, the staged and the unstaged changes with
// Stage and Unstage, then the history of every branch as a graph. Row 2 (GitBar.swift) has the branch, Fetch, Pull and
// Push; the app reads git and runs every write (GitRepo.swift).
import "./git.css"
import { ask, type Change, type Commit, how, menu, type RepoState, receive, report } from "./lib/bridge"

document.body.innerHTML = `
<p id="failure" hidden></p>
<main id="home" hidden>
  <form id="commit">
    <textarea id="message" rows="1" placeholder="Message" aria-label="Message"></textarea>
    <button id="commit-button" type="submit" disabled>Commit</button>
  </form>
  <section id="staged"></section>
  <section id="unstaged"></section>
  <section id="history"><header><h2>History</h2></header><div class="rows"></div></section>
</main>`

const failure = document.getElementById("failure")!
const home = document.getElementById("home")!
const form = document.getElementById("commit") as HTMLFormElement
const message = document.getElementById("message") as HTMLTextAreaElement
const commitButton = document.getElementById("commit-button") as HTMLButtonElement
let state: RepoState = { root: "" }
let shown = ""
let committing = false

const WORDS: Record<string, string> = {
  M: "Modified", T: "Type changed", A: "Added", D: "Deleted", R: "Renamed", U: "Untracked", C: "Conflict",
}

function element<K extends keyof HTMLElementTagNameMap>(tag: K, className = "", text = "") {
  const node = document.createElement(tag)
  node.className = className
  node.textContent = text
  return node
}

/** An SF Symbol the app sent, drawn in the text's color. */
function symbol(name: string, className = "symbol") {
  const node = element("span", className)
  node.style.setProperty("--symbol", `var(--sf-${name.replaceAll(".", "-")})`)
  node.ariaHidden = "true"
  return node
}

function show(next: RepoState) {
  const json = JSON.stringify(next)
  if (json === shown) return
  shown = json
  state = next
  failure.hidden = !next.failure
  failure.textContent = next.failure ?? ""
  home.hidden = Boolean(next.failure)
  if (next.failure) return
  const staged = next.staged ?? [], unstaged = next.unstaged ?? []
  section("staged", "Staged Changes", staged, true)
  section("unstaged", "Changes", unstaged, false)
  document.querySelector("#history .rows")!.replaceChildren(...graph(next.commits ?? []))
  ready()
}

/** A list's header with its count and Stage All or Unstage All, then a row per file; the staged list only when it
 * has files. */
function section(id: string, title: string, changes: Change[], staged: boolean) {
  const node = document.getElementById(id)!
  node.hidden = staged && !changes.length
  const header = element("header")
  header.append(element("h2", "", title), element("span", "count", changes.length ? String(changes.length) : ""))
  if (changes.length) {
    const all = staged ? "Unstage All" : "Stage All"
    header.append(button(staged ? "minus" : "plus", all, () => write({ op: "repo", do: staged ? "unstageAll" : "stageAll" })))
  }
  const rows = element("div", "rows")
  rows.append(...(changes.length ? changes.map((change) => changeRow(change, staged)) : [element("p", "empty", "No changes")]))
  node.replaceChildren(header, rows)
}

function button(name: string, label: string, action: () => void) {
  const node = element("button", "icon")
  node.title = label
  node.ariaLabel = label
  node.append(symbol(name))
  node.onclick = (event) => {
    event.stopPropagation()
    action()
  }
  return node
}

function write(message: { op: "repo"; do: "stage" | "unstage" | "stageAll" | "unstageAll"; path?: string; oldPath?: string | null }) {
  // A failure shows git's message in the card's toast.
  ask(message).catch(() => undefined)
}

/** A row that opens with a click, Return or Space: in the card, or with ⌘ in a new tab, with ⌥ to the side; its
 * menu has the three. Its button holds what it shows; a Stage button is the row's own, beside it: a button in a
 * button is no button to VoiceOver. */
function row(label: string, target: { arg: string; at?: string }) {
  const node = element("div", "row"), open = element("button", "open")
  open.ariaLabel = label
  node.append(open)
  node.onclick = (event) => report({ op: "open", kind: "git", ...target, how: how(event) })
  node.oncontextmenu = (event) => menu(event, { kind: "git", ...target })
  return { node, open }
}

function changeRow(change: Change, staged: boolean) {
  const name = change.path.replace(/\/$/, ""), slash = name.lastIndexOf("/") + 1
  const { node, open } = row(`${WORDS[change.letter] ?? change.letter}: ${name}`,
    { arg: `${state.root} uncommitted`, at: change.path })
  node.id = `${staged ? "staged" : "change"}.${change.path}`
  node.title = change.oldPath ? `${change.oldPath} → ${name}` : name
  const toggle = staged ? "Unstage" : "Stage"
  open.append(symbol("doc"), element("span", "name", name.slice(slash)),
    element("span", "folder", name.slice(0, Math.max(slash - 1, 0))))
  node.append(
    button(staged ? "minus" : "plus", `${toggle} ${name}`, () =>
      write({ op: "repo", do: staged ? "unstage" : "stage", path: change.path, oldPath: change.oldPath }),
    ),
    element("span", `letter ${change.letter}`, change.letter),
  )
  return node
}

const LANE = 14, HEIGHT = 28
const COLORS = ["var(--accent)", "var(--finished)", "var(--working)", "var(--needs-you)", "var(--error)"]
const color = (lane: number) => COLORS[lane % COLORS.length]
const x = (lane: number) => 9 + lane * LANE

/** The history: one graph width for every row, so the subjects line up. */
function graph(commits: Commit[]) {
  const lanes = Math.max(0, ...commits.flatMap(({ lane, children, parents, through }) => [lane, ...children, ...parents, ...through]))
  const width = x(lanes) + 9
  return commits.map((commit) => commitRow(commit, width))
}

/** A row of the graph as `Git.graph` lays it out: lines from the row's top into the dot, from the dot to its
 *  bottom, and straight through; a line between two lanes takes the color of the one that is not the dot's. HEAD's
 *  dot is a ring. */
function commitRow(commit: Commit, width: number) {
  const { hash, subject, date, lane, children, parents, through, refs } = commit
  const mid = HEIGHT / 2
  const line = (from: number, y1: number, to: number, y2: number) =>
    `<path d="M${x(from)} ${y1} C${x(from)} ${mid} ${x(to)} ${mid} ${x(to)} ${y2}" stroke="${color(from === lane ? to : from)}"/>`
  const head = refs.some((ref) => ref === "HEAD" || ref.startsWith("HEAD -> "))
  const dot = head
    ? `<circle cx="${x(lane)}" cy="${mid}" r="4.5" fill="var(--card)" stroke="${color(lane)}" stroke-width="2"/>`
    : `<circle cx="${x(lane)}" cy="${mid}" r="4" fill="${color(lane)}"/>`
  const { node, open } = row(subject, { arg: `${state.root} ${hash}` })
  node.id = `commit.${hash}`
  node.classList.add("commit")
  node.title = `${subject}\n${commit.author} · ${hash.slice(0, 10)}`
  open.insertAdjacentHTML("afterbegin", `<svg width="${width}" height="${HEIGHT}" fill="none" stroke-width="1.5">${[
    ...through.map((at) => line(at, 0, at, HEIGHT)),
    ...children.map((at) => line(at, 0, lane, mid)),
    ...parents.map((at) => line(lane, mid, at, HEIGHT)),
  ].join("")}${dot}</svg>`)
  open.append(...refs.flatMap(badge), element("span", "name", subject), element("span", "hash", hash.slice(0, 7)),
    element("span", "when", when(date)))
  return node
}

/** A branch, remote branch or tag on its commit; the checked-out branch on the accent. */
function badge(ref: string) {
  const head = ref.startsWith("HEAD -> "), full = head ? ref.slice(8) : ref
  const kinds: [string, string][] = [["refs/heads/", "arrow.triangle.branch"], ["refs/remotes/", "cloud"], ["tag: refs/tags/", "tag"]]
  const kind = kinds.find(([prefix]) => full.startsWith(prefix))
  // `origin/HEAD` names another one; a detached HEAD is `HEAD`.
  if (full.endsWith("/HEAD") || (!kind && full !== "HEAD")) return []
  const node = element("span", head || full === "HEAD" ? "badge head" : "badge")
  node.append(symbol(kind?.[1] ?? "arrow.triangle.branch"), element("span", "", kind ? full.slice(kind[0].length) : "HEAD"))
  return [node]
}

/** Today's time, this year's day, or an older day with its year. */
function when(ms: number) {
  const date = new Date(ms), now = new Date()
  if (date.toDateString() === now.toDateString()) return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
  const year = date.getFullYear() === now.getFullYear() ? undefined : "numeric"
  return date.toLocaleDateString(undefined, { year, month: "short", day: "numeric" })
}

// The message grows to five lines, then scrolls. Commit is on the accent when it can commit: a message and staged
// files. ⌘↩ commits.
function ready() {
  commitButton.disabled = committing || !message.value.trim() || !state.staged?.length
}
message.addEventListener("input", () => {
  message.style.height = "auto"
  message.style.height = `${message.scrollHeight}px`
  ready()
})
message.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && event.metaKey) {
    event.preventDefault()
    form.requestSubmit()
  }
})
form.addEventListener("submit", async (event) => {
  event.preventDefault()
  if (commitButton.disabled) return
  const text = message.value
  committing = true
  ready()
  const done = await ask({ op: "repo", do: "commit", message: text }).catch(() => false)
  committing = false
  if (done && message.value === text) {
    message.value = ""
    message.style.height = "auto"
  }
  ready()
})

receive((message) => {
  if (message.op === "repo") show(message.repo)
})

const { repo, symbols } = (await ask({ op: "repo", do: "read" }).catch((error: Error) => ({
  repo: { root: "", failure: error.message },
  symbols: {},
}))) as { repo: RepoState; symbols: Record<string, string> }
// In a style sheet: the app sets the root's own style to its colors.
const sheet = element("style")
sheet.textContent = `:root { ${Object.entries(symbols).map(([name, url]) => `--sf-${name.replaceAll(".", "-")}: url(${url});`).join(" ")} }`
document.head.append(sheet)
show(repo)
report({ op: "ready" })
