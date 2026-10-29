// The Files card (Oriel/Plugins/Files): the root's tree, each folder listed as it opens, row 2's filter over every
// path, and a collapsed Git section with the changes and a graph of the history.
import { FileTree, type FileTreeBatchOperation, type FileTreeDirectoryHandle, type GitStatus } from "@pierre/trees"
import "./files.css"
import { type Change, type Commit, type Entry, arg as root, ask, receive, report } from "./lib/bridge"

document.body.innerHTML = `
<p id="message" hidden></p>
<div id="tree"></div>
<section id="git" hidden>
  <button id="git-head" aria-label="Git" aria-expanded="false"><span class="chevron"></span>Git</button>
  <div id="git-body"><h2>Changes</h2><div id="changes"></div><h2>History</h2><div id="history"></div></div>
</section>`

/** Each folder's entries as the tree has them: `""` is the root, and a folder's path ends in `/`, as the tree's. */
const children = new Map<string, Set<string>>()
/** Folders in the tree that no listing filled yet: closed ones, and those of the filter's paths. */
const unlisted = new Set<string>()
const ignored = new Set<string>()
let changes: Change[] = []
/** The root, when it is a git repository's root. */
let repo: string | undefined
/** Row 2's filter, and every path of the root that it searches, loaded at its first letter. */
let filter = ""
let paths: Promise<void> | undefined
/** The root's last listing failed. */
let failed = false

const STATUS: Record<string, GitStatus> = {
  M: "modified", T: "modified", C: "modified", A: "added", D: "deleted", R: "renamed", U: "untracked",
}
/** Paths in the tree are from the root; `/` as the root gives no `//`. */
const base = root.replace(/\/$/, "")
const parent = (path: string) => path.slice(0, path.lastIndexOf("/", path.length - 2) + 1)
const folder = (path: string) => tree.getItem(path) as FileTreeDirectoryHandle | null

const tree = new FileTree({
  paths: [],
  density: "compact",
  // A folder with one folder in it is two rows, as in the Finder.
  flattenEmptyDirectories: false,
  fileTreeSearchMode: "hide-non-matches",
  // A click on a match ends the filter and shows the file in the whole tree: row 2's field empties with it.
  onSearchChange: (value) => {
    if (value === null && filter) {
      filter = ""
      report({ op: "filter", text: "" })
    }
  },
  unsafeCSS: `:host {
    --trees-bg-override: transparent; --trees-fg-override: var(--text); --trees-fg-muted-override: var(--dim);
    --trees-accent-override: var(--accent); --trees-font-size-override: var(--font-size);
    --trees-padding-inline-override: 4px; --trees-border-color-override: var(--divider);
    --trees-selected-bg-override: color-mix(in srgb, var(--accent) 22%, transparent);
    --truncate-marker-background-color: transparent;
    --trees-git-modified-color-override: var(--needs-you); --trees-git-deleted-color-override: var(--error);
    --trees-git-added-color-override: var(--finished); --trees-git-untracked-color-override: var(--finished);
    --trees-git-renamed-color-override: var(--finished);
  }
  [data-item-contains-git-change="true"] > [data-item-section="git"] { opacity: 1; }`,
})
const host = document.getElementById("tree")!
const message = document.getElementById("message")!
tree.render({ containerWrapper: host })

/** One at a time: two listings of a folder at once would add its entries twice. */
let queue = Promise.resolve()
const run = (work: () => Promise<void>) => (queue = queue.then(work, work))
/** A change while a refresh waits joins it: a build writes many times a second. */
let due = false

/** Adds the path, and the folders above it the tree does not have yet. */
function put(path: string, operations: FileTreeBatchOperation[]) {
  let added = false
  for (let at = path; at; at = parent(at)) {
    const set = children.get(parent(at)) ?? children.set(parent(at), new Set()).get(parent(at))!
    // A link to a folder or a submodule is a folder in a listing and a file in git's paths.
    if (set.has(at) || set.has(at.endsWith("/") ? at.slice(0, -1) : at + "/")) break
    set.add(at)
    if (at.endsWith("/")) unlisted.add(at)
    added = true
  }
  // The tree makes the folders above a path itself.
  if (added) operations.push({ type: "add", path })
}

function forget(path: string) {
  for (const child of children.get(path) ?? []) forget(child)
  children.delete(path)
  unlisted.delete(path)
  ignored.delete(path)
}

/** The folder's entries from the machine, in place of what the tree had in it. */
async function list(at: string) {
  unlisted.delete(at)
  let entries: Entry[]
  try {
    entries = await ask({ op: "list", path: at ? `${base}/${at.slice(0, -1)}` : root, repo })
  } catch {
    if (at) return
    children.clear()
    unlisted.clear()
    ignored.clear()
    tree.resetPaths([])
    failed = true
    show()
    return
  }
  if (!at) failed = false
  // An empty folder too: a refresh lists it again.
  if (!children.has(at)) children.set(at, new Set())
  const now = entries.map((entry) => at + entry.name + (entry.folder ? "/" : ""))
  const kept = new Set(now)
  const operations: FileTreeBatchOperation[] = []
  for (const path of children.get(at) ?? []) {
    if (kept.has(path)) continue
    children.get(at)?.delete(path)
    forget(path)
    operations.push({ type: "remove", path, recursive: true })
  }
  entries.forEach((entry, index) => {
    put(now[index], operations)
    if (entry.ignored) ignored.add(now[index])
    else ignored.delete(now[index])
  })
  tree.batch(operations)
  showStatus()
  if (!at) show()
}
/** The message over the tree: the root's listing failed, or the filter matches nothing (the tree would show all). */
function show() {
  const none = tree.isSearchOpen() && !tree.getSearchMatchingPaths().length
  host.hidden = none
  message.hidden = !failed && !none
  message.textContent = failed ? `Can't list ${root}` : none ? "No matching files" : ""
}

function showStatus() {
  tree.setGitStatus([
    ...changes.flatMap(({ letter, path }) => (STATUS[letter] ? [{ path, status: STATUS[letter] }] : [])),
    ...[...ignored].map((path) => ({ path, status: "ignored" as const })),
  ])
}

/** The git section and the open folders again, after a change on the machine. A closed folder lists when it opens. */
async function refresh() {
  await git()
  await list("")
  for (const at of [...children.keys()]) {
    if (!at || unlisted.has(at) || !children.has(at)) continue
    if (folder(at)?.isExpanded()) await list(at)
    else unlisted.add(at)
  }
}

// A folder lists when the user opens it; the filter's matches open without it.
// ponytail: walks every folder not listed at each change of the tree (after a filter, all of the repository's); walk
// the visible rows if a big repository's arrow keys lag.
tree.subscribe(() => {
  show()
  if (tree.isSearchOpen()) return
  for (const at of unlisted) {
    if (!folder(at)?.isExpanded()) continue
    unlisted.delete(at)
    run(() => list(at))
  }
})

receive((message) => {
  if (message.op === "filter") {
    filter = message.text
    paths ??= filter ? run(loadPaths).catch(() => {}) : undefined
    void (paths ?? queue).then(() => (filter ? tree.setSearch(filter) : tree.closeSearch()))
  } else if (message.op === "collapse") {
    for (const at of children.keys()) if (at) folder(at)?.collapse()
  } else if (message.op === "changed" && !due) {
    due = true
    // The next filter reads the paths again, for the files made since.
    if (!filter) paths = undefined
    run(async () => {
      due = false
      await refresh()
    })
  }
})

/** Every file of the root, for the filter: added under the folders no listing filled yet. */
async function loadPaths() {
  const operations: FileTreeBatchOperation[] = []
  for (const path of (await ask({ op: "paths", repo }).catch(() => [])) as string[]) put(path, operations)
  tree.batch(operations)
}

// The Git section: the root's changes and its last 100 commits.
const section = document.getElementById("git")!
const head = document.getElementById("git-head")!
head.addEventListener("click", () => head.setAttribute("aria-expanded", String(section.classList.toggle("open"))))

async function git() {
  const answer: { changes: Change[]; commits: Commit[] } | null = await ask({ op: "git" }).catch(() => null)
  repo = answer ? root : undefined
  section.hidden = !answer
  changes = answer?.changes ?? []
  showStatus()
  if (!answer) return
  const none = Object.assign(document.createElement("p"), { className: "empty", textContent: "No changes" })
  document.getElementById("changes")!.replaceChildren(...(changes.length ? changes.map(changeRow) : [none]))
  document.getElementById("history")!.replaceChildren(...answer.commits.map(commitRow))
}

function row(id: string, label: string, ...parts: [string, string][]) {
  const element = document.createElement("div")
  element.className = "row"
  element.id = id
  element.setAttribute("role", "button")
  element.tabIndex = 0
  element.setAttribute("aria-label", label)
  element.append(...parts.map(([kind, text]) => Object.assign(document.createElement("span"), { className: kind, textContent: text })))
  return element
}

const WORDS: Record<string, string> = {
  M: "Modified", T: "Type changed", A: "Added", D: "Deleted", R: "Renamed", U: "Untracked", C: "Conflict",
}

function changeRow({ letter, path }: Change) {
  const name = path.replace(/\/$/, ""), slash = name.lastIndexOf("/") + 1
  const element = row(`change.${path}`, `${WORDS[letter] ?? letter}: ${name}`, [`letter ${letter}`, letter], ["name", name.slice(slash)], ["dim", name.slice(0, slash)])
  element.dataset.change = path
  return element
}

const LANE = 12, HEIGHT = 24
const COLORS = ["var(--accent)", "var(--finished)", "var(--working)", "var(--needs-you)", "var(--error)"]
const color = (lane: number) => COLORS[lane % COLORS.length]
const x = (lane: number) => 8 + lane * LANE

/** A row of the graph as `Git.graph` lays it out: lines from the row's top into the dot, from the dot to its
 *  bottom, and straight through; a line between two lanes takes the color of the one that is not the dot's. */
function commitRow({ hash, subject, date, lane, children, parents, through }: Commit) {
  const mid = HEIGHT / 2
  const line = (from: number, y1: number, to: number, y2: number) =>
    `<path d="M${x(from)} ${y1} C${x(from)} ${mid} ${x(to)} ${mid} ${x(to)} ${y2}" stroke="${color(from === lane ? to : from)}"/>`
  const width = x(Math.max(lane, ...children, ...parents, ...through)) + 8
  const when = new Date(date)
  const year = when.getFullYear() === new Date().getFullYear() ? undefined : "numeric"
  const element = row(`commit.${hash}`, subject, ["name", subject], ["dim", hash.slice(0, 7)],
    ["when", when.toLocaleDateString(undefined, { year, month: "short", day: "numeric" })])
  element.classList.add("commit")
  element.dataset.commit = hash
  element.insertAdjacentHTML("afterbegin", `<svg width="${width}" height="${HEIGHT}" fill="none" stroke-width="1.5">${[
    ...through.map((at) => line(at, 0, at, HEIGHT)),
    ...children.map((at) => line(at, 0, lane, mid)),
    ...parents.map((at) => line(lane, mid, at, HEIGHT)),
  ].join("")}<circle cx="${x(lane)}" cy="${mid}" r="3.5" fill="${color(lane)}"/></svg>`)
  return element
}

/** Double-click, ⌘-click or Return on what `pick` finds opens it. In the capture phase, before the tree's own click
 *  (⌘ adds to its selection); the first click may end the filter and move the rows, so a double-click opens what its
 *  first click was on. */
function onOpen(element: HTMLElement, pick: (node: HTMLElement) => string | undefined, open: (value: string) => void) {
  const under = (event: Event) => {
    const node = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && pick(n) !== undefined)
    return node && pick(node)
  }
  let first: string | undefined
  element.addEventListener(
    "click",
    (event) => {
      const at = under(event)
      if (event.detail === 1) first = at
      const picked = event.metaKey ? at : event.detail === 2 ? first : undefined
      if (picked === undefined) return
      event.stopPropagation()
      open(picked)
    },
    true,
  )
  element.addEventListener("keydown", (event) => {
    const at = event.key === "Enter" ? under(event) : undefined
    if (at !== undefined) open(at)
  })
}

// A double-click on a folder opens or closes it once, as in the Finder: its second click toggles nothing.
host.addEventListener(
  "click",
  (event) => {
    const folder = event.composedPath().some((n) => n instanceof HTMLElement && n.dataset.itemType === "folder")
    if (folder && event.detail >= 2) event.stopPropagation()
  },
  true,
)

// A file: in a new tab with its kind; a change: the diff of the uncommitted changes at that file; a commit: its diff.
onOpen(host, (node) => (node.dataset.itemType === "file" ? node.dataset.itemPath : undefined), (path) =>
  report({ op: "open", arg: `${base}/${path}` }),
)
onOpen(document.getElementById("changes")!, (node) => node.dataset.change, (path) =>
  report({ op: "open", kind: "diff", arg: `${root} uncommitted`, at: path }),
)
onOpen(document.getElementById("history")!, (node) => node.dataset.commit, (hash) =>
  report({ op: "open", kind: "diff", arg: `${root} ${hash}` }),
)

// A page loaded again (a new root, a crashed process) starts with no filter.
report({ op: "filter", text: "" })
run(async () => {
  await git()
  await list("")
})
