// The File Explorer's home: the root's tree, each folder listed as it opens, git's letters, and row 2's filter over
// every path. A file opens in the card, a new tab or a pane to the side.
import { FileTree, type FileTreeBatchOperation, type FileTreeDirectoryHandle, type GitStatus } from "@pierre/trees"
import type { Change } from "@oriel/plugin-api"
import { how, menu, name, open, type Place, type Reveal } from "./place"

const STATUS: Record<string, GitStatus> = {
  M: "modified", T: "modified", C: "modified", A: "added", D: "deleted", R: "renamed", U: "untracked",
}
const parent = (path: string) => path.slice(0, path.lastIndexOf("/", path.length - 2) + 1)

/** SF Symbols' shapes, as Finder's list and Xcode's navigator draw them: a thin disclosure chevron (the tree turns
 *  it), `folder.fill` in the accent, `doc` in secondary. */
const svg = (body: string) =>
  `url("data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">${body}</svg>`)}")`
const FOLDER = svg(`<path d="M1.5 4.3c0-.7.6-1.3 1.3-1.3h3.4c.3 0 .6.1.9.4L8.2 4.5h5c.7 0 1.3.6 1.3 1.3v6.4c0 .7-.6 1.3-1.3 1.3H2.8c-.7 0-1.3-.6-1.3-1.3z"/>`)
const DOC = svg(`<path fill="none" stroke="black" stroke-width="1.1" stroke-linejoin="round" d="M4.6 1.6h4.3l3.5 3.5v8.3c0 .6-.4 1-1 1H4.6c-.6 0-1-.4-1-1V2.6c0-.6.4-1 1-1zM8.8 1.7v2.9c0 .4.2.6.6.6h2.9"/>`)
const sprite = `<svg data-icon-sprite aria-hidden="true" width="0" height="0">
  <symbol id="oriel-chevron" viewBox="0 0 16 16"><path d="M4.5 6.25 8 9.75l3.5-3.5" fill="none" stroke="currentColor"
    stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="oriel-none" viewBox="0 0 16 16"></symbol></svg>`

// The filter's matches are a second tree, of the files whose name matches with their folders: Pierre's own search
// matches the whole path.
const look = {
  // A folder with one folder in it is two rows, as in the Finder.
  flattenEmptyDirectories: false,
  icons: {
    set: "minimal" as const,
    spriteSheet: sprite,
    remap: { "file-tree-icon-chevron": "oriel-chevron", "file-tree-icon-file": "oriel-none" },
  },
  unsafeCSS: `:host {
    --trees-bg-override: transparent; --trees-fg-override: var(--text); --trees-fg-muted-override: var(--dim);
    --trees-accent-override: var(--accent); --trees-font-size-override: var(--font-size);
    --trees-padding-inline-override: 6px; --trees-border-color-override: var(--divider);
    --trees-item-height: 24px; --trees-border-radius-override: 6px; --trees-level-gap-override: 12px;
    --trees-item-row-gap-override: 5px; --trees-item-padding-x-override: 6px;
    --trees-bg-muted-override: color-mix(in srgb, var(--text) 6%, transparent);
    --trees-selected-bg-override: color-mix(in srgb, var(--accent) 24%, transparent);
    --trees-selected-fg-override: var(--text); --trees-focus-ring-width-override: 0px;
    --trees-indent-guide-bg-override: var(--divider);
    --truncate-marker-background-color: transparent;
    --trees-git-modified-color-override: var(--needs-you); --trees-git-deleted-color-override: var(--error);
    --trees-git-added-color-override: var(--finished); --trees-git-untracked-color-override: var(--finished);
    --trees-git-renamed-color-override: var(--finished);
  }
  [data-item-contains-git-change="true"] > [data-item-section="git"] { opacity: 1; }
  [data-type="item"] > [data-item-section="icon"] { width: 34px; justify-content: space-between; color: var(--dim); }
  [data-type="item"] > [data-item-section="icon"]::after { content: ""; flex: none; width: 16px; height: 16px;
    background: var(--dim); -webkit-mask: ${DOC} center / 16px no-repeat; }
  [data-item-type="folder"] > [data-item-section="icon"]::after { background: var(--accent); -webkit-mask-image: ${FOLDER}; }
  [data-item-selected="true"] > [data-item-section="icon"] { color: var(--dim); }`,
}
/** Row 2: the root's name, whose menu lists the folders above it, nearest first, then Choose Folder…. */
function header({ oriel }: Place, top: string) {
  const parents: string[] = []
  for (let at = top; at !== "/"; parents.push(at)) at = at.slice(0, at.lastIndexOf("/")) || "/"
  const items = parents.map((at) => ({ value: at === "/" ? "/" : `${at}/`, title: name(at), symbol: "folder" }))
  oriel.controls.set("root", { title: name(top), value: "", items: [...items, "-", { value: "choose", title: "Choose Folder…" }] })
}

/** The root's tree in `place.root`, its rows listed; git's letters and a landing's row come after. */
export async function show(place: Place): Promise<Reveal> {
  const { oriel, root, keep } = place
  /** The argument is a folder's, with its `/`. Paths in the tree are from the root; `/` as the root gives no `//`. */
  const base = place.arg.replace(/\/$/, "")
  const top = base || "/"
  const folder = (path: string) => tree.getItem(path) as FileTreeDirectoryHandle | null
  header(place, top)
  /** A folder of the root's menu, or one Choose Folder… picks: the tree rooted there, as the card's next place. */
  const move = async (value: string) => {
    const picked = value === "choose" ? await oriel.pick.folder(top) : value
    if (picked) oriel.card.go(picked.endsWith("/") ? picked : `${picked}/`)
  }

  /** Each folder's entries as the tree has them: `""` is the root, and a folder's path ends in `/`, as the tree's. */
  const children = new Map<string, Set<string>>()
  /** Folders in the tree that no listing filled yet: closed ones, and those of the filter's paths. */
  const unlisted = new Set<string>()
  const ignored = new Set<string>()
  let changes: Change[] = []
  /** Row 2's filter, every path of the root that it searches (loaded at its first letter), and how many match. */
  let filter = ""
  let paths: Promise<void> | undefined
  let matched = 0
  /** The root's last listing failed. */
  let failed = false

  /** Whether git's state shows: the root is a repository's root, and git runs. */
  let repository = false

  root.innerHTML = `<p id="message" hidden></p><div id="tree"></div><div id="matches" hidden></div>`
  const tree = new FileTree({ paths: [], ...look })
  const results = new FileTree({ paths: [], ...look })
  const host = root.querySelector<HTMLElement>("#tree")!
  const message = root.querySelector<HTMLElement>("#message")!
  const matches = root.querySelector<HTMLElement>("#matches")!
  tree.render({ containerWrapper: host })
  results.render({ containerWrapper: matches })
  keep(() => {
    tree.cleanUp()
    results.cleanUp()
  })

  /** One at a time: two listings of a folder at once would add its entries twice. None once the place left. */
  let queue = Promise.resolve()
  const run = (work: () => Promise<void>) => {
    const live = async () => (place.live() ? work() : undefined)
    return (queue = queue.then(live, live))
  }
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
    let entries: { name: string; folder: boolean; ignored: boolean }[]
    try {
      entries = await oriel.files.list(at ? `${base}/${at.slice(0, -1)}` : top)
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
      // A root inside a repository, but not its root, shows none of git's state.
      if (entry.ignored && repository) ignored.add(now[index])
      else ignored.delete(now[index])
    })
    tree.batch(operations)
    showStatus()
    if (!at) show()
  }

  /** The message over the trees: the root's listing failed, or the filter matches nothing. */
  function show() {
    const none = Boolean(filter) && !matched
    message.hidden = !failed && !none
    message.textContent = failed ? `Can't list ${top}` : none ? "No matching files" : ""
  }

  /** The files whose name has the filter's text, with their folders, open.
   *  ponytail: the first 5,000, as the native variant; a search on the machine when roots get bigger. */
  function match() {
    const text = filter.toLowerCase()
    const found = [...children.values()].flatMap((set) =>
      [...set].filter((path) => !path.endsWith("/") && path.slice(path.lastIndexOf("/") + 1).toLowerCase().includes(text)),
    ).slice(0, 5000)
    matched = found.length
    host.hidden = Boolean(filter)
    matches.hidden = !filter
    results.resetPaths(filter ? found : [], { initialExpandedPaths: [...new Set(found.flatMap(folders))] })
    show()
  }

  /** The folders above a path. */
  function folders(path: string): string[] {
    const above = parent(path)
    return above ? [above, ...folders(above)] : []
  }

  function showStatus() {
    const status = [
      ...changes.flatMap(({ letter, path }) => (STATUS[letter] ? [{ path, status: STATUS[letter] }] : [])),
      ...[...ignored].map((path) => ({ path, status: "ignored" as const })),
    ]
    tree.setGitStatus(status)
    results.setGitStatus(status)
  }

  /** git's letters and the open folders again, after a change on the machine. A closed folder lists when it opens. */
  async function refresh() {
    await list("")
    await git()
    for (const at of [...children.keys()]) {
      if (!at || unlisted.has(at) || !children.has(at)) continue
      if (folder(at)?.isExpanded()) await list(at)
      else unlisted.add(at)
    }
  }

  /** The root's changes from git, for the letters; none when the root is no repository's root. */
  async function git() {
    changes = repository ? await oriel.git.status(top).catch(() => []) : []
    showStatus()
  }

  /** A path under the root (absolute, as the app sends it) shown: its folders listed and open, its row selected in the
   *  middle of the card. */
  async function reveal(path: string) {
    if (!path.startsWith(`${base}/`)) return
    const relative = path.slice(base.length + 1)
    for (const above of folders(relative).reverse()) {
      if (unlisted.has(above) || !children.has(above)) await list(above)
      folder(above)?.expand()
    }
    const item = tree.getItem(relative) ?? tree.getItem(`${relative}/`)
    if (!item) return
    item.select()
    tree.focusPath(item.getPath())
    tree.scrollToPath(item.getPath())
  }

  // A folder lists when the user opens it.
  // ponytail: walks every folder not listed at each change of the tree (after a filter, all of the repository's); walk
  // the visible rows if a big repository's arrow keys lag.
  keep(tree.subscribe(() => {
    for (const at of unlisted) {
      if (!folder(at)?.isExpanded()) continue
      unlisted.delete(at)
      run(() => list(at))
    }
  }))

  keep(oriel.on("control", ({ id, value }) => {
    if (id === "filter") {
      filter = String(value ?? "")
      paths ??= filter ? run(loadPaths).catch(() => {}) : undefined
      void (paths ?? queue).then(match)
    } else if (id === "collapse") {
      for (const at of children.keys()) if (at) folder(at)?.collapse()
    } else if (id === "root") {
      void move(String(value ?? ""))
    }
  }))

  // After each change under the root, and once when the card shows again.
  keep(oriel.files.watch(top, () => {
    if (due) return
    due = true
    // The next filter reads the paths again, for the files made since.
    if (!filter) paths = undefined
    run(async () => {
      due = false
      await refresh()
      if (filter) match()
    })
  }))

  /** Every file of the root, for the filter: added under the folders no listing filled yet. */
  async function loadPaths() {
    const operations: FileTreeBatchOperation[] = []
    for (const path of await oriel.files.paths(top).catch(() => [])) put(path, operations)
    tree.batch(operations)
  }

  /** The row's path from the root, and whether it is a folder's. */
  const row = (event: Event) => {
    const node = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && Boolean(n.dataset.itemPath))
    return node && { path: `${base}/${node.dataset.itemPath!.replace(/\/$/, "")}`, folder: node.dataset.itemType === "folder" }
  }

  for (const trees of [host, matches]) {
    // A file: double-click or Return in the card, ⌘-click in a new tab, ⌥-click to the side. In the capture phase,
    // before the tree's own click (⌘ adds to its selection). A double-click on a folder opens or closes it once, as in
    // the Finder: its second click toggles nothing.
    trees.addEventListener(
      "click",
      (event) => {
        const at = row(event)
        // A ⌘- or ⌥-double-click opens once.
        if (at && event.detail > 1 && (event.metaKey || event.altKey)) return event.stopPropagation()
        if (!at || !(event.metaKey || event.altKey || event.detail >= 2)) return
        if (at.folder && !event.metaKey && !event.altKey) return event.stopPropagation()
        event.stopPropagation()
        open(oriel, at.folder ? `${at.path}/` : at.path, how(event))
      },
      true,
    )
    trees.addEventListener("keydown", (event) => {
      const at = event.key === "Enter" ? row(event) : undefined
      if (at && !at.folder) open(oriel, at.path, how(event))
    })
    // The app's menu: Open (Open as Root on a folder), Open in New Tab, Open to the Side.
    trees.addEventListener("contextmenu", (event) => {
      const at = row(event)
      if (at) void menu(oriel, event, at.folder ? `${at.path}/` : at.path)
      else event.preventDefault()
    })
  }

  // The repository first, so the first listing dims what git ignores; the rows, then git's letters.
  await run(async () => {
    repository = await oriel.git.root(top).then((found) => found === top, () => false)
    await list("")
  })
  run(async () => {
    if (place.at) await reveal(place.at)
    await git()
  })
  return (at) => void run(() => reveal(at))
}
