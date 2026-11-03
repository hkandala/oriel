// The File Explorer's home: the root's tree, each folder listed as it opens, git's letters, and row 2's filter over
// every path. A file opens in the card, a new tab or a pane to the side.
import { FileTree, type FileTreeBatchOperation, type FileTreeDirectoryHandle, type GitStatus } from "@pierre/trees"
import type { Change } from "@oriel/plugin-api"
import { how, menu, open, type Place, type Reveal } from "./place"

const STATUS: Record<string, GitStatus> = {
  M: "modified", T: "modified", C: "modified", A: "added", D: "deleted", R: "renamed", U: "untracked",
}
const parent = (path: string) => path.slice(0, path.lastIndexOf("/", path.length - 2) + 1)

/** As Finder's list and Xcode's navigator draw them: a thin disclosure chevron (the tree turns it), `folder.fill` in
 *  the Finder's folder blue (files.css); files take the tree's own icons by type. */
const sprite = `<svg data-icon-sprite aria-hidden="true" width="0" height="0">
  <symbol id="oriel-chevron" viewBox="0 0 16 16"><path d="M4.5 6.25 8 9.75l3.5-3.5" fill="none" stroke="currentColor"
    stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</svg>`

// The filter's matches are a second tree, of the files whose name matches with their folders: Pierre's own search
// matches the whole path.
const look = {
  // A folder with one folder in it is two rows, as in the Finder.
  flattenEmptyDirectories: false,
  icons: {
    set: "complete" as const,
    spriteSheet: sprite,
    remap: { "file-tree-icon-chevron": "oriel-chevron" },
  },
  unsafeCSS: `:host {
    --trees-bg-override: transparent; --trees-fg-override: var(--text); --trees-fg-muted-override: var(--dim);
    --trees-accent-override: var(--accent); --trees-font-size-override: var(--font-size);
    --trees-padding-inline-override: 6px; --trees-border-color-override: var(--divider);
    --trees-item-height: 24px; --trees-border-radius-override: 6px; --trees-level-gap-override: 12px;
    --trees-item-row-gap-override: 5px; --trees-item-padding-x-override: 6px;
    --trees-bg-muted-override: color-mix(in srgb, var(--text) 6%, transparent);
    --trees-selected-bg-override: color-mix(in srgb, var(--accent) 24%, transparent);
    --trees-selected-fg-override: var(--text); --trees-focus-ring-width-override: 1.5px;
    --trees-focus-ring-color-override: var(--accent); --trees-focus-ring-offset-override: -1.5px;
    --trees-selected-focused-border-color-override: var(--accent);
    --trees-indent-guide-bg-override: var(--divider);
    --truncate-marker-background-color: transparent;
    --trees-git-modified-color-override: var(--needs-you); --trees-git-deleted-color-override: var(--error);
    --trees-git-added-color-override: var(--finished); --trees-git-untracked-color-override: var(--finished);
    --trees-git-renamed-color-override: var(--finished);
  }
  [data-item-contains-git-change="true"] > [data-item-section="git"] { opacity: 1; }
  [data-type="item"] > [data-item-section="icon"] { width: 34px; justify-content: flex-end; color: var(--dim); }
  [data-item-type="folder"] > [data-item-section="icon"] { justify-content: space-between; }
  [data-item-type="folder"] > [data-item-section="icon"]::after { content: ""; flex: none; width: 16px; height: 16px;
    background: var(--folder-blue); -webkit-mask: var(--folder) center / 16px no-repeat; }
  [data-item-selected="true"] > [data-item-section="icon"] { color: var(--dim); }
  :host(:not([data-keys])) [data-type="item"]::before { outline: none !important; }`,
}
/** Whether a name is a dotfile's, which the tree hides unless row 2's Hidden Files is on. */
const dotted = (path: string) => /(^|\/)\.[^/]/.test(path)

/** The root's tree in `place.root`, its rows listed; git's letters and a landing's row come after. */
export async function show(place: Place): Promise<Reveal> {
  const { oriel, root, keep } = place
  /** The argument is a folder's, with its `/`. Paths in the tree are from the root; `/` as the root gives no `//`. */
  const base = place.arg.replace(/\/$/, "")
  const top = base || "/"
  const folder = (path: string) => tree.getItem(path) as FileTreeDirectoryHandle | null
  const above = top === "/" ? "" : top.slice(0, top.lastIndexOf("/")) || "/"
  oriel.controls.set("root", { value: top })
  /** A typed path, or the folder Choose Folder… picks (no path: the field's folder button): the tree rooted there,
   *  as the card's next place. A path that is no folder shakes the field. */
  const move = async (path?: string) => {
    const root = path ?? (await oriel.pick.folder(top))
    if (!root) return
    if (!(await oriel.files.info(root).then((info) => info.folder, () => false))) {
      return oriel.controls.set("root", { refused: true })
    }
    oriel.card.go(root === "/" ? "/" : `${root}/`)
  }
  /** Hidden files show: row 2's eye, kept with the card's controls. */
  let dotfiles = oriel.controls.get("hidden-files") === true

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

  /** Whether git's state shows: the root is a repository's root, and git runs. Asked with each listing of the root,
   *  so a `git init` in the tree shows git's letters. */
  let repository = false
  const rooted = () => oriel.git.root(top).then((found) => found === top, () => false)

  root.innerHTML = `<button id="up" aria-label="Parent Folder" hidden><span class="icon"></span>..</button>
    <div id="message" hidden><span class="symbol"></span><p></p></div><div id="tree"></div><div id="matches" hidden></div>`
  const tree = new FileTree({ paths: [], ...look })
  const results = new FileTree({ paths: [], ...look })
  const host = root.querySelector<HTMLElement>("#tree")!
  const message = root.querySelector<HTMLElement>("#message")!
  const matches = root.querySelector<HTMLElement>("#matches")!
  // The parent folder as the root, on a double-click of `..`; none at `/`, nor while the filter has text.
  const up = root.querySelector<HTMLElement>("#up")!
  up.hidden = !above
  // A double-click's second click, or a press (Return, VoiceOver: no clicks counted).
  up.onclick = (event) => event.detail !== 1 && oriel.card.go(above === "/" ? "/" : `${above}/`)
  // ↓ from `..`: the first row.
  up.onkeydown = (event) => {
    if (event.key !== "ArrowDown") return
    event.preventDefault()
    take(tree.getVisibleRows(0, 0)[0]?.path)
  }
  tree.render({ containerWrapper: host })
  results.render({ containerWrapper: matches })
  keep(() => {
    tree.cleanUp()
    results.cleanUp()
  })
  /** The focus ring shows from an arrow key on, and goes with a click, as `:focus-visible` does. */
  const ring = (on: boolean) => {
    root.toggleAttribute("data-keys", on)
    for (const each of [tree, results]) each.getFileTreeContainer()?.toggleAttribute("data-keys", on)
  }
  root.addEventListener("keydown", (event) => {
    // Before a key moved it, the row with the keyboard shows nothing: the first ↓ goes to the first row (`..` when
    // shown), the first ↑ to the last, rather than one past the row nobody sees.
    const shown = filter ? results : tree, vertical = event.key === "ArrowDown" || event.key === "ArrowUp"
    const plain = !event.shiftKey && !event.metaKey && !event.altKey && !event.ctrlKey
    if (vertical && plain && !root.hasAttribute("data-keys") && document.activeElement !== up
      && !shown.getSelectedPaths().length) {
      event.preventDefault()
      event.stopPropagation()
      if (event.key === "ArrowUp") shown.focusLastItem()
      else if (up.hidden) shown.focusFirstItem()
      else up.focus()
    }
    if (event.key.startsWith("Arrow")) ring(true)
  }, true)
  root.addEventListener("pointerdown", () => ring(false), true)

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

  /** The folder's entries from the machine, in place of what the tree had in it; `rooted` is asked meanwhile, as
   *  whether the root is a repository's (the first listing). */
  async function list(at: string, rooted?: Promise<boolean>) {
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
    } finally {
      if (rooted) repository = await rooted
    }
    if (!at) failed = false
    // An empty folder too: a refresh lists it again.
    if (!children.has(at)) children.set(at, new Set())
    if (!dotfiles) entries = entries.filter((entry) => !entry.name.startsWith("."))
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

  /** The message in the middle of the card: the root's listing failed, the filter matches nothing, or the root has
   *  nothing to show. */
  function show() {
    const none = Boolean(filter) && !matched, empty = !filter && !failed && children.get("")?.size === 0
    message.hidden = !failed && !none && !empty
    message.querySelector("p")!.textContent = failed ? `Can't list ${top}`
      : none ? "No matching files" : empty ? "This folder is empty" : ""
    const icon = failed ? "folder.badge.questionmark" : empty ? "folder" : "magnifyingglass"
    if (!message.hidden && message.dataset.icon !== icon) {
      message.dataset.icon = icon
      void oriel.symbol(icon, 30).then((url) => message.style.setProperty("--symbol", `url(${url})`), () => {})
    }
  }

  /** The files whose name has the filter's text, with their folders, open.
   *  ponytail: the first 5,000, as the native variant; a search on the machine when roots get bigger. */
  function match() {
    const text = filter.toLowerCase()
    const named = (path: string) => path.slice(path.lastIndexOf("/") + 1).toLowerCase().includes(text)
    const found = [...children.values()].flatMap((set) =>
      [...set].filter((path) => !path.endsWith("/") && (dotfiles || !dotted(path)) && named(path)),
    ).slice(0, 5000)
    matched = found.length
    host.hidden = Boolean(filter)
    matches.hidden = !filter
    up.hidden = !above || Boolean(filter)
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
    await list("", rooted())
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

  /** A path under the root (absolute, as the app sends it) shown: its folders listed and open, its row selected, in the
   *  middle of the card, or only scrolled into view (`nearest`). */
  async function reveal(path: string, offset?: "nearest") {
    if (!path.startsWith(`${base}/`)) return
    const relative = path.slice(base.length + 1)
    // A dotfile shows only with the hidden files: the eye turns on (Show in File Explorer on `.gitignore`).
    if (!dotfiles && dotted(relative)) {
      dotfiles = true
      oriel.controls.set("hidden-files", { value: true })
      await refresh()
    }
    for (const above of folders(relative).reverse()) {
      if (unlisted.has(above) || !children.has(above)) await list(above)
      folder(above)?.expand()
    }
    const item = tree.getItem(relative) ?? tree.getItem(`${relative}/`)
    if (!item) return
    only(tree, item.getPath())
    tree.focusPath(item.getPath())
    tree.scrollToPath(item.getPath(), offset && { offset })
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

  oriel.on("control", ({ id, value }) => {
    if (id === "filter") {
      filter = String(value ?? "")
      paths ??= filter ? run(loadPaths).catch(() => {}) : undefined
      void (paths ?? queue).then(match).catch(console.error)
    } else if (id === "collapse") {
      for (const at of children.keys()) if (at) folder(at)?.collapse()
    } else if (id === "root") {
      void move(value === undefined ? undefined : String(value))
    } else if (id === "hidden-files") {
      dotfiles = value === true
      run(refresh).catch(console.error)
      // The filter's paths again, with the dotfiles or without.
      paths = filter ? run(loadPaths).catch(() => {}) : undefined
      void (paths ?? queue).then(match).catch(console.error)
    }
  })
  // ⌘F: the filter takes the keyboard.
  oriel.on("find", () => oriel.controls.set("filter", { focus: true }))

  // After each change under the root, and once when the card shows again.
  oriel.files.watch(top, () => {
    if (due) return
    due = true
    // The next filter reads the paths again, for the files made since.
    if (!filter) paths = undefined
    run(async () => {
      due = false
      await refresh()
      if (filter) match()
    }).catch(console.error)
  })

  /** Every file of the root, for the filter: added under the folders no listing filled yet. */
  async function loadPaths() {
    const operations: FileTreeBatchOperation[] = []
    for (const path of await oriel.files.paths(top).catch(() => [])) {
      if (dotfiles || !dotted(path)) put(path, operations)
    }
    tree.batch(operations)
  }

  /** The row's absolute path, its id in the tree, and whether it is a folder's. */
  const row = (event: Event) => {
    const node = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && Boolean(n.dataset.itemPath))
    const id = node?.dataset.itemPath
    return id === undefined ? undefined
      : { path: `${base}/${id.replace(/\/$/, "")}`, id, folder: node!.dataset.itemType === "folder" }
  }
  /** The click is on a folder's chevron, at the left of its icon. */
  const chevron = (event: MouseEvent) => {
    const icon = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && n.dataset.itemSection === "icon")
    const right = icon?.querySelector("svg")?.getBoundingClientRect().right
    return right !== undefined && event.clientX <= right
  }

  for (const trees of [host, matches]) {
    // A file: double-click or Return in the card, ⌘-click in a new tab, ⌥-click to the side; a folder the same way
    // as the root. As in the Finder, a click on a folder's name only selects it: its chevron, → and Return open it, so
    // a double-click never shows it open first. In the capture phase, before the tree's own click (⌘ adds to its
    // selection, a click toggles a folder).
    trees.addEventListener(
      "click",
      (event) => {
        const at = row(event)
        if (!at) return
        // A ⌘- or ⌥-double-click opens once.
        if (event.detail > 1 && (event.metaKey || event.altKey)) return event.stopPropagation()
        const toggle = at.folder && chevron(event)
        if (event.metaKey || event.altKey || (event.detail >= 2 && !toggle)) {
          event.stopPropagation()
          open(oriel, at.folder ? `${at.path}/` : at.path, how(event))
        } else if (at.folder && !toggle && event.detail === 1 && !event.shiftKey && !event.ctrlKey) {
          event.stopPropagation()
          only(filter ? results : tree, at.id)
          take(at.id)
        }
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

  // ↑ on the first row: `..` (hidden while the filter has text).
  host.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowUp" || up.hidden || tree.getFocusedPath() !== tree.getVisibleRows(0, 0)[0]?.path) return
    event.preventDefault()
    event.stopPropagation()
    up.focus()
  }, true)

  /** The row alone selected: a kept tree still has the row it opened before. */
  function only(shown: FileTree, path: string) {
    for (const at of shown.getSelectedPaths()) shown.getItem(at)?.deselect()
    shown.getItem(path)?.select()
  }

  /** The shown tree takes the keyboard, on `path`, else its focused row, else its first: ↑↓ move, → opens, ← closes or
   *  goes to the parent. A row with the keyboard shows its ring once a key moved it. */
  function take(path?: string) {
    const shown = filter ? results : tree
    path ??= shown.getFocusedPath() ?? shown.getVisibleRows(0, 0)[0]?.path
    if (!path) return
    // Any row first: the tree moves the keyboard to its focused row only while it holds it.
    const any = shown.getFileTreeContainer()?.shadowRoot?.querySelector<HTMLElement>("button[data-item-path]")
    any?.focus({ preventScroll: true })
    shown.focusPath(path)
  }
  // The app gives the card the keyboard (also as it opens, from main.ts); a frame later, so a click that gave a row
  // the keyboard keeps it (else the tree scrolls to its old row between the press and the release).
  const given = () => requestAnimationFrame(() => {
    if (place.shown() && document.activeElement !== up && !(filter ? results : tree).getFileTreeContainer()?.shadowRoot?.activeElement) {
      take()
    }
  })
  addEventListener("focus", given)
  keep(() => removeEventListener("focus", given))

  // Whether the root is a repository's with the first listing, so it dims what git ignores (one wait for both, as
  // each starts a process); a landing's row before the tree shows; then git's letters.
  await run(() => list("", rooted()))
  if (place.at) await run(() => reveal(place.at!))
  run(git)
  // Back on the kept tree: the row it came back from, scrolled into view only when it is out of it.
  return (at) => void run(() => reveal(at, "nearest"))
}
