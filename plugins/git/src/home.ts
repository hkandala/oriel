// The Git card's home, a page of its own (`oriel.pages`): the commit message and Commit, the staged and the unstaged
// changes with Revert, Stage and Unstage (or "No changes"), then the history of every branch as a graph. Row 2 has the
// branch, Working Tree, Fetch, Pull and Push. A folder that is no repository shows Initialize Repository instead.
import type { Change, Commit, Page } from "@oriel/plugin-api"
import { element, failed, fileIcon, home, how, keep, menu, nameAndFolder, open, oriel, symbol } from "./lib"

const WORDS: Record<string, string> = {
  M: "Modified", T: "Type changed", A: "Added", D: "Deleted", R: "Renamed", U: "Untracked", C: "Conflict",
}

const LANE = 14, HEIGHT = 28
const COLORS = ["var(--accent)", "var(--finished)", "var(--working)", "var(--needs-you)", "var(--error)"]
const color = (lane: number) => COLORS[lane % COLORS.length]
const x = (lane: number) => 9 + lane * LANE

/** Today's time, this year's day, or an older day with its year. */
function when(ms: number) {
  const date = new Date(ms), now = new Date()
  if (date.toDateString() === now.toDateString()) return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
  const year = date.getFullYear() === now.getFullYear() ? undefined : "numeric"
  return date.toLocaleDateString(undefined, { year, month: "short", day: "numeric" })
}

/** The home of a root in its page, drawn once read, at a change or a commit (`at`) when it lands on one. Its header
 *  controls, handlers and watch are the page's own (`place.oriel`). */
export async function make(place: Page, root: string) {
  const api = place.oriel
  const page = element("div")
  page.id = "home"
  page.innerHTML = `
  <p id="failure" hidden></p>
  <div id="no-repository" class="placeholder" hidden>
    <span class="symbol" style="--symbol: var(--sf-folder-badge-questionmark)"></span>
    <h2>Not a Git repository</h2><p class="path"></p>
    <button id="initialize" type="button">Initialize Repository</button>
  </div>
  <main hidden>
    <div id="clean" class="placeholder" hidden>
      <span class="symbol" style="--symbol: var(--sf-checkmark-circle)"></span><h2>No changes</h2>
    </div>
    <div id="changes">
      <form id="commit">
        <textarea id="message" rows="1" placeholder="Message" aria-label="Message"></textarea>
        <button id="commit-button" type="submit" disabled>Commit</button>
      </form>
      <section id="staged"></section>
      <section id="unstaged"></section>
    </div>
    <section id="history"><header class="title"><h2>History</h2></header><div class="rows"></div></section>
  </main>`
  place.element.append(page)

  const notice = page.querySelector<HTMLElement>("#failure")!
  const noRepository = page.querySelector<HTMLElement>("#no-repository")!
  const initialize = page.querySelector<HTMLButtonElement>("#initialize")!
  const clean = page.querySelector<HTMLElement>("#clean")!
  const changesBox = page.querySelector<HTMLElement>("#changes")!
  const content = page.querySelector("main")!
  const form = page.querySelector<HTMLFormElement>("#commit")!
  const message = page.querySelector<HTMLTextAreaElement>("#message")!
  const commitButton = page.querySelector<HTMLButtonElement>("#commit-button")!

  let staged: Change[] = []
  let unstaged: Change[] = []
  /** git's error when the root is no repository (or git cannot run). */
  let failure: string | undefined
  /** The history's length asked for: Show More adds 500. */
  let limit = 500
  let branches: { name: string; remote: boolean; current: boolean }[] = []
  /** The writes with a spinner (fetch, pull, push, switch, commit) in the order they run: the app runs a card's writes
   *  one at a time. */
  const running: string[] = []
  /** What the page drew last: a read that finds the same draws nothing. */
  let drawn = ""

  let loading: Promise<void> | undefined
  let again = false

  /** Reads everything again and draws what changed; a call during a read reads once more after it. */
  async function load() {
    if (loading) {
      again = true
      return loading
    }
    // A read that throws ends here too: the next change or write reads again.
    loading = (async () => {
      try {
        do {
          again = false
          await read()
        } while (again)
      } finally {
        loading = undefined
      }
    })()
    return loading
  }

  async function read() {
    const asked = limit
    const [changes, head, list, commits] = await Promise.allSettled([
      oriel.git.changes(root), oriel.git.head(root), oriel.git.branches(root), oriel.git.log(root, { limit: asked }),
    ])
    // git's message when git cannot read a repository; none when the folder is no repository: it can become one.
    // ponytail: any failure of `git.root` (a folder gone, a repository git refuses) reads as none; match git's message
    // if those must show it.
    const bare = changes.status === "rejected" && (await oriel.git.root(root).catch(() => "")) === null
    failure = changes.status === "rejected" ? (changes.reason as Error).message : undefined
    branches = list.status === "fulfilled" ? list.value : []
    const branch = head.status === "fulfilled" ? head.value : null
    api.controls.set("git.branch", {
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
    api.controls.set("git.pull", count(branch?.behind ?? 0, "Pull"))
    api.controls.set("git.push", count(branch?.ahead ?? 0, "Push"))
    buttons()
    // None before the first commit. A full page may have more.
    const history = commits.status === "fulfilled" ? commits.value : []
    const state = changes.status === "fulfilled"
      ? { ...changes.value, commits: history, more: history.length >= asked }
      : { failure, bare }
    // Keys sorted: the app's replies come in any key order, and a draw under a click loses the click.
    const json = JSON.stringify(state, (_, value) => value && typeof value === "object" && !Array.isArray(value)
      ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => (a < b ? -1 : 1)))
      : value)
    if (json === drawn) return
    drawn = json
    draw(state)
  }

  /** The branch, Working Tree and the three buttons: a spinner on the one that runs, all off while one runs or git cannot
   *  read (Working Tree only then). */
  function buttons() {
    const off = Boolean(failure || running.length)
    api.controls.set("git.branch", { busy: running[0] === "switch", enabled: branches.length > 0 && !running.length })
    for (const name of ["fetch", "pull", "push"]) api.controls.set(`git.${name}`, { busy: running[0] === name, enabled: !off })
    // Nothing to show where git cannot read.
    api.controls.set("git.working", { enabled: !failure })
  }

  function draw(state: {
    staged?: Change[]; unstaged?: Change[]; commits?: Commit[]; more?: boolean; failure?: string; bare?: boolean
  }) {
    noRepository.hidden = !state.bare
    // ponytail: any user's home reads `~`: the plugin API has no home folder.
    noRepository.querySelector(".path")!.textContent = root.replace(/^\/(Users|home)\/[^/]+(?=\/|$)/, "~")
    notice.hidden = !state.failure || Boolean(state.bare)
    notice.textContent = state.failure ?? ""
    content.hidden = Boolean(state.failure)
    if (state.failure) return
    staged = state.staged ?? []
    unstaged = state.unstaged ?? []
    // With no changes, the placeholder alone: no lists, no message, no Commit.
    clean.hidden = Boolean(staged.length || unstaged.length)
    changesBox.hidden = !clean.hidden
    section("staged", "Staged Changes", staged, true)
    section("unstaged", "Changes", unstaged, false)
    const commits = state.commits ?? []
    const rows = page.querySelector("#history .rows")!
    rows.replaceChildren(...(commits.length ? graph(commits) : [element("p", "empty", "No commits yet")]))
    if (state.more) {
      const more = element("button", "more", "Show More")
      more.onclick = () => {
        more.disabled = true
        limit += 500
        void load()
      }
      rows.append(more)
    }
    enable()
  }

  /** A list's header with its count, Revert All, and Stage All or Unstage All, then a row per file; only when it has
   *  files. */
  function section(id: string, title: string, changes: Change[], staged: boolean) {
    const node = page.querySelector<HTMLElement>(`#${id}`)!
    node.hidden = !changes.length
    const header = element("header", "title")
    header.append(element("h2", "", title), element("span", "count", String(changes.length)))
    const revertAll = element("button", "all", "Revert All")
    revertAll.ariaLabel = `Revert All ${title}`
    const all = element("button", "all", staged ? "Unstage All" : "Stage All")
    revertAll.onclick = () => void revert(changes)
    all.onclick = () => void write(staged ? oriel.git.unstage(root) : oriel.git.stage(root))
    header.append(revertAll, all)
    const rows = element("div", "rows")
    rows.append(...changes.map((change) => changeRow(change, staged)))
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
    const name = change.path.replace(/\/$/, ""), [base, folder] = nameAndFolder(name)
    const { node, open } = row(`${WORDS[change.letter] ?? change.letter}: ${name}`, `${home(root)} uncommitted`, change.path)
    node.id = `${staged ? "staged" : "change"}.${change.path}`
    node.title = change.oldPath ? `${change.oldPath} → ${name}` : name
    const toggle = staged ? "Unstage" : "Stage", letter = element("span", `letter ${change.letter}`, change.letter)
    // The label says it.
    letter.ariaHidden = "true"
    open.append(fileIcon(name), element("span", "name", base), element("span", "folder", folder))
    node.append(
      button("arrow.uturn.backward", `Revert ${name}`, () => void revert([change])),
      button(staged ? "minus" : "plus", `${toggle} ${name}`, () =>
        write(staged ? oriel.git.unstage(root, paths(change)) : oriel.git.stage(root, paths(change)))),
      letter,
    )
    return node
  }

  /** A change's path, and a rename's old one. */
  const paths = (change: Change) => [change.path, ...(change.oldPath ? [change.oldPath] : [])]

  /** Asks, then puts the files back as HEAD has them (both lists'). The question names the new files (untracked, or
   *  added in the index), which go. */
  async function revert(changes: Change[]) {
    const added = new Set(staged.filter((change) => change.letter === "A").map((change) => change.path))
    const fresh = changes.filter((change) => change.letter === "U" || added.has(change.path))
      .map((change) => nameAndFolder(change.path)[0])
    const named = fresh.length > 3 ? `${fresh.slice(0, 2).join(", ")} and ${fresh.length - 2} more` : fresh.join(", ")
    const base = nameAndFolder(changes[0].path)[0]
    const deletes = fresh.length ? ` This deletes the new ${fresh.length > 1 ? "files" : "file"} ${named}.` : ""
    const question = changes.length > 1 ? `Revert all ${changes.length} files?${deletes}`
      : fresh.length ? `Delete the new file ${base}?` : `Revert changes to ${base}?`
    const picked = await oriel.toast(`${question} This cannot be undone.`, ["Cancel", "Revert"], { destructive: true })
    if (picked !== "Revert") return
    await write(oriel.git.revert(root, changes.flatMap(paths)))
  }

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
    const kinds: [string, string][] = [["refs/heads/", "source.branch"], ["refs/remotes/", "cloud"], ["tag: refs/tags/", "tag"]]
    const kind = kinds.find(([prefix]) => full.startsWith(prefix))
    // `origin/HEAD` names another one; a detached HEAD is `HEAD`.
    if (full.endsWith("/HEAD") || (!kind && full !== "HEAD")) return []
    const node = element("span", head || full === "HEAD" ? "badge head" : "badge")
    node.append(symbol(kind?.[1] ?? "source.branch"), element("span", "", kind ? full.slice(kind[0].length) : "HEAD"))
    return [node]
  }

  // The header's picks on the home: a branch, Working Tree, Fetch, Pull, Push.
  api.on("control", ({ id, value }) => {
    if (id === "git.working") oriel.card.go(`${home(root)} uncommitted`)
    else if (id === "git.branch") {
      const branch = branches.find((branch) => branch.name === value)
      if (branch && !branch.current) void write(oriel.git.switch(root, branch.name), "switch")
    } else if (id === "git.fetch") void write(oriel.git.fetch(root), "fetch")
    else if (id === "git.pull") void write(oriel.git.pull(root), "pull")
    else if (id === "git.push") void write(oriel.git.push(root), "push")
  })

  initialize.onclick = () => {
    // Once at a time.
    initialize.disabled = true
    void write(oriel.git.init(root)).then(() => (initialize.disabled = false))
  }

  // The message grows to five lines, then scrolls; the card keeps it (`state`). Commit is on the accent when it can
  // commit: a message and changes. With none staged it is Commit All, which stages everything first. ⌘↩ commits.
  let committing = false
  function enable() {
    commitButton.textContent = staged.length ? "Commit" : "Commit All"
    commitButton.disabled = committing || !message.value.trim() || !(staged.length || unstaged.length)
  }
  function grow() {
    message.style.height = "auto"
    message.style.height = `${message.scrollHeight}px`
  }
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
    const done = await write((staged.length ? Promise.resolve() : oriel.git.stage(root)).then(() => oriel.git.commit(root, text)),
      "commit")
    committing = false
    // Not a message typed meanwhile.
    if (done && message.value === text) {
      message.value = ""
      message.style.height = "auto"
      keep({ draft: "" })
    }
    enable()
  })

  // While the page shows, a read after each change under the root; when it shows again, one for the changes meanwhile.
  api.files.watch(root, () => void load())
  message.value = oriel.state.get<{ draft?: string }>()?.draft ?? ""
  await load()
  document.title = ""
  // Once its form shows: hidden, it has no height.
  if (message.value) grow()
  // From a diff's Git Home: at the change or the commit it opened.
  const at = place.at ?? "", ids = at.startsWith(`${home(root)} `) ? [`commit.${at.split(" ").pop()}`]
    : [`change.${at}`, `staged.${at}`]
  if (at) [...page.querySelectorAll("[id]")].find((node) => ids.includes(node.id))?.scrollIntoView({ block: "center" })
}
