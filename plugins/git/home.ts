// The Git card's home: the commit message and Commit, the staged and the unstaged changes with Stage and Unstage, then
// the history of every branch as a graph. Row 2 has the branch, Fetch, Pull and Push (`main.ts`).
import type { Change, Commit } from "@oriel/plugin-api"
import { control, element, failed, home, how, keep, menu, open, oriel, symbol } from "./lib"

const page = element("div")
page.id = "home"
page.hidden = true
page.innerHTML = `
<p id="failure" hidden></p>
<main hidden>
  <form id="commit">
    <textarea id="message" rows="1" placeholder="Message" aria-label="Message"></textarea>
    <button id="commit-button" type="submit" disabled>Commit</button>
  </form>
  <section id="staged"></section>
  <section id="unstaged"></section>
  <section id="history"><header class="title"><h2>History</h2></header><div class="rows"></div></section>
</main>`
document.body.append(page)

const notice = page.querySelector<HTMLElement>("#failure")!
const content = page.querySelector("main")!
const form = page.querySelector<HTMLFormElement>("#commit")!
const message = page.querySelector<HTMLTextAreaElement>("#message")!
const commitButton = page.querySelector<HTMLButtonElement>("#commit-button")!

let root = ""
let staged: Change[] = []
/** git's error when the root is no repository (or git cannot run). */
let failure: string | undefined
let branches: { name: string; remote: boolean; current: boolean }[] = []
/** The writes with a spinner (fetch, pull, push, switch, commit) in the order they run: the app runs a card's writes
 *  one at a time. */
const running: string[] = []
/** What the page drew last: a read that finds the same draws nothing. */
let drawn = ""

const WORDS: Record<string, string> = {
  M: "Modified", T: "Type changed", A: "Added", D: "Deleted", R: "Renamed", U: "Untracked", C: "Conflict",
}

/** Shows the home of `next`, landing at a change or a commit the card comes back from. */
export async function show(next: string, at?: string) {
  if (next !== root) {
    root = next
    drawn = ""
  }
  page.hidden = false
  await load()
  // Once its form shows: hidden, it has no height.
  if (message.value) grow()
  // Back from a diff: at the change or the commit it opened.
  const landing = at?.startsWith(`${home(root)} `)
    ? document.getElementById(`commit.${at.split(" ").pop()}`)
    : at ? (document.getElementById(`change.${at}`) ?? document.getElementById(`staged.${at}`)) : null
  landing?.scrollIntoView({ block: "center" })
}

export const hide = () => {
  page.hidden = true
}

let loading: Promise<void> | undefined
let again = false

/** Reads everything again and draws what changed; a call during a read reads once more after it. */
export async function load() {
  if (loading) {
    again = true
    return loading
  }
  loading = (async () => {
    do {
      again = false
      await read()
    } while (again)
    loading = undefined
  })()
  return loading
}

async function read() {
  const at = root
  const [changes, head, list, commits] = await Promise.allSettled([
    oriel.git.changes(at), oriel.git.head(at), oriel.git.branches(at), oriel.git.log(at),
  ])
  if (at !== root) return
  failure = changes.status === "rejected" ? (changes.reason as Error).message : undefined
  branches = list.status === "fulfilled" ? list.value : []
  const branch = head.status === "fulfilled" ? head.value : null
  control("git.branch", {
    title: branch?.branch ?? "—",
    value: branch?.branch ?? "",
    items: [
      ...branches.filter((b) => !b.remote).map((b) => ({ value: b.name, title: b.name })),
      ...(branches.some((b) => b.remote)
        ? ["-" as const, { title: "Remote" }, ...branches.filter((b) => b.remote).map((b) => ({ value: b.name, title: b.name }))]
        : []),
    ],
  })
  const count = (n: number, word: string) => (n > 0 ? { badge: n, label: `${word}, ${n} ${word === "Pull" ? "behind" : "ahead"}` }
    : { badge: 0, label: "" })
  control("git.pull", count(branch?.behind ?? 0, "Pull"))
  control("git.push", count(branch?.ahead ?? 0, "Push"))
  buttons()
  // None before the first commit.
  const state = changes.status === "fulfilled"
    ? { ...changes.value, commits: commits.status === "fulfilled" ? commits.value : [] }
    : { failure }
  // Keys sorted: the app's replies come in any key order, and a draw under a click loses the click.
  const json = JSON.stringify(state, (_, value) => value && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => (a < b ? -1 : 1)))
    : value)
  if (json === drawn) return
  drawn = json
  draw(state)
}

/** The branch and the three buttons: a spinner on the one that runs, all off while one runs or git cannot read. */
function buttons() {
  const off = Boolean(failure || running.length)
  control("git.branch", { busy: running[0] === "switch", enabled: branches.length > 0 && !running.length })
  for (const name of ["fetch", "pull", "push"]) control(`git.${name}`, { busy: running[0] === name, enabled: !off })
}

function draw(state: { staged?: Change[]; unstaged?: Change[]; commits?: Commit[]; failure?: string }) {
  notice.hidden = !state.failure
  notice.textContent = state.failure ?? ""
  content.hidden = Boolean(state.failure)
  if (state.failure) return
  staged = state.staged ?? []
  section("staged", "Staged Changes", staged, true)
  section("unstaged", "Changes", state.unstaged ?? [], false)
  const commits = state.commits ?? []
  page.querySelector("#history .rows")!.replaceChildren(
    ...(commits.length ? graph(commits) : [element("p", "empty", "No commits yet")]),
  )
  enable()
}

/** A list's header with its count and Stage All or Unstage All, then a row per file; the staged list only when it
 * has files. */
function section(id: string, title: string, changes: Change[], staged: boolean) {
  const node = page.querySelector<HTMLElement>(`#${id}`)!
  node.hidden = staged && !changes.length
  const header = element("header", "title")
  header.append(element("h2", "", title), element("span", "count", changes.length ? String(changes.length) : ""))
  if (changes.length) {
    const all = staged ? "Unstage All" : "Stage All"
    header.append(button(staged ? "minus" : "plus", all, () => write(staged ? oriel.git.unstage(root) : oriel.git.stage(root))))
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

/** After a write, a read; a failure shows git's message in the toast. */
async function write(done: Promise<void>, busy?: string) {
  if (busy) {
    running.push(busy)
    buttons()
  }
  const worked = await done.then(() => true, (error: Error) => {
    void failed(error)
    return false
  })
  if (busy) {
    running.splice(running.indexOf(busy), 1)
    buttons()
  }
  await load()
  return worked
}

/** A row that opens with a click, Return or Space: in the card, or with ⌘ in a new tab, with ⌥ to the side; its
 * menu has the three. Its button holds what it shows; a Stage button is the row's own, beside it: a button in a
 * button is no button to VoiceOver. */
function row(label: string, arg: string, at?: string) {
  const node = element("div", "row"), button = element("button", "open")
  button.ariaLabel = label
  node.append(button)
  node.onclick = (event) => open(arg, { how: how(event), at, plugin: "git" })
  node.oncontextmenu = (event) => void menu(event, arg, at)
  return { node, open: button }
}

function changeRow(change: Change, staged: boolean) {
  const name = change.path.replace(/\/$/, ""), slash = name.lastIndexOf("/") + 1
  const { node, open } = row(`${WORDS[change.letter] ?? change.letter}: ${name}`, `${home(root)} uncommitted`, change.path)
  node.id = `${staged ? "staged" : "change"}.${change.path}`
  node.title = change.oldPath ? `${change.oldPath} → ${name}` : name
  const toggle = staged ? "Unstage" : "Stage", letter = element("span", `letter ${change.letter}`, change.letter)
  // The label says it.
  letter.ariaHidden = "true"
  open.append(symbol("doc"), element("span", "name", name.slice(slash)),
    element("span", "folder", name.slice(0, Math.max(slash - 1, 0))))
  const paths = [change.path, ...(change.oldPath ? [change.oldPath] : [])]
  node.append(
    button(staged ? "minus" : "plus", `${toggle} ${name}`, () =>
      write(staged ? oriel.git.unstage(root, paths) : oriel.git.stage(root, paths))),
    letter,
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
  const names = refs.flatMap(badge)
  const label = [subject, ...names.map((name) => name.textContent), when(date)].join(", ")
  const { node, open } = row(label, `${home(root)} ${hash}`)
  node.id = `commit.${hash}`
  node.classList.add("commit")
  node.title = `${subject}\n${commit.author} · ${hash.slice(0, 10)}`
  open.insertAdjacentHTML("afterbegin", `<svg width="${width}" height="${HEIGHT}" fill="none" stroke-width="1.5">${[
    ...through.map((at) => line(at, 0, at, HEIGHT)),
    ...children.map((at) => line(at, 0, lane, mid)),
    ...parents.map((at) => line(lane, mid, at, HEIGHT)),
  ].join("")}${dot}</svg>`)
  open.append(...names, element("span", "name", subject), element("span", "hash", hash.slice(0, 7)),
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

/** The header's picks on the home: a branch, Fetch, Pull, Push. */
export function pick(id: string, value?: string) {
  if (id === "git.branch") {
    const branch = branches.find((branch) => branch.name === value)
    if (branch && !branch.current) void write(oriel.git.switch(root, branch.name), "switch")
  } else if (id === "git.fetch") void write(oriel.git.fetch(root), "fetch")
  else if (id === "git.pull") void write(oriel.git.pull(root), "pull")
  else if (id === "git.push") void write(oriel.git.push(root), "push")
}

// The message grows to five lines, then scrolls; the card keeps it (`state`). Commit is on the accent when it can
// commit: a message and staged files. ⌘↩ commits.
let committing = false
function enable() {
  commitButton.disabled = committing || !message.value.trim() || !staged.length
}
function grow() {
  message.style.height = "auto"
  message.style.height = `${message.scrollHeight}px`
}
message.value = oriel.state.get<{ draft?: string }>()?.draft ?? ""
message.addEventListener("input", () => {
  grow()
  enable()
  keep({ draft: message.value })
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
  enable()
  const done = await write(oriel.git.commit(root, text), "commit")
  committing = false
  // Not a message typed meanwhile.
  if (done && message.value === text) {
    message.value = ""
    message.style.height = "auto"
    keep({ draft: "" })
  }
  enable()
})
