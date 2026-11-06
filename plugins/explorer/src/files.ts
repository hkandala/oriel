// The File Explorer's home: the root's tree, each folder listed as it opens, git's letters, the find bar's filter over
// every path, and the status bar. A file opens in the card, a new tab or a pane to the side.
import { FileTree, type FileTreeBatchOperation, type FileTreeDirectoryHandle, type FileTreeRenameEvent,
  type GitStatus } from "@pierre/trees"
import type { Change } from "@ovvi/plugin-api"
import { footer } from "./footer"
import { stack } from "./stack"
import { choose, how, menu, open, own, type Place, type Reveal, symbols } from "./place"

const STATUS: Record<string, GitStatus> = {
  M: "modified", T: "modified", C: "modified", A: "added", D: "deleted", R: "renamed", U: "untracked",
}
const parent = (path: string) => path.slice(0, path.lastIndexOf("/", path.length - 2) + 1)
/** `..`, the tree's first row: a folder with no entries, so it scrolls with the rows and takes their clicks, keys and
 *  menu. The tree's own sort puts it first.
 *  ponytail: a name at the root that starts with a character before `.` (`-`, `(`, `#`) sorts above it; a comparator
 *  of our own if that matters. */
const UP = "../"

/** As Finder's list and Xcode's navigator draw them: a thin disclosure chevron (the tree turns it), `folder.fill` in
 *  the Finder's folder blue (files.css); files take the tree's own icons by type. */
const sprite = `<svg data-icon-sprite aria-hidden="true" width="0" height="0">
  <symbol id="ovvi-chevron" viewBox="0 0 16 16"><path d="M4.5 6.25 8 9.75l3.5-3.5" fill="none" stroke="currentColor"
    stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</svg>`

// The filter's matches are a second tree, of the files whose name matches with their folders: Pierre's own search
// matches the whole path.
const look = {
  // A folder with one folder in it is two rows, as in the Finder.
  flattenEmptyDirectories: false,
  // The open folders above the view stay at its top, nested, as in Xcode's navigator.
  stickyFolders: true,
  icons: {
    set: "complete" as const,
    spriteSheet: sprite,
    remap: { "file-tree-icon-chevron": "ovvi-chevron" },
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
  /* As the Finder's list: the selection in gray while the tree does not have the keyboard. */
  :host(:not(:focus-within)) { --trees-selected-bg-override: color-mix(in srgb, var(--text) 12%, transparent); }
  [data-item-contains-git-change="true"] > [data-item-section="git"] { opacity: 1; }
  [data-type="item"] > [data-item-section="icon"] { width: 34px; justify-content: flex-end; color: var(--dim); }
  [data-item-type="folder"] > [data-item-section="icon"] { justify-content: space-between; }
  [data-item-type="folder"] > [data-item-section="icon"]::after { content: ""; flex: none; width: 16px; height: 16px;
    background: var(--folder-blue); -webkit-mask: var(--folder) center / 16px no-repeat; }
  [data-item-path="${UP}"] > [data-item-section="icon"] > svg { visibility: hidden; }
  [data-item-selected="true"] > [data-item-section="icon"] { color: var(--dim); }
  /* The sticky folders on the card, with no band (stack.ts): the view masked under them, their copy over it. */
  :host { position: relative; }
  :host([data-stack]) [data-file-tree-virtualized-scroll] {
    -webkit-mask: linear-gradient(transparent var(--stack), #000 var(--stack)); }
  [data-stack-copy] { position: absolute; z-index: 5; pointer-events: none; }
  [data-stack-copy] [data-hover] { background-color: var(--trees-bg-muted); }
  /* Inside its box: the row's name clips what goes past it. */
  [data-item-rename-input] { border-radius: 4px; background: var(--card); outline: 1.5px solid var(--accent);
    outline-offset: -1.5px; }
  :host(:not([data-keys])) [data-type="item"]::before { outline: none !important; }`,
}
/** Whether a name is a dotfile's, which the tree hides unless row 2's Hidden Files is on. */
const dotted = (path: string) => /(^|\/)\.[^/]/.test(path)

/** The root's tree in `place.root`, its rows listed; git's letters and a landing's row come after. */
export async function show(place: Place): Promise<Reveal> {
  const { ovvi, root, keep } = place
  /** The argument is a folder's, with its `/`. Paths in the tree are from the root; `/` as the root gives no `//`. */
  const base = place.arg.replace(/\/$/, "")
  const top = base || "/"
  const folder = (path: string) => tree.getItem(path) as FileTreeDirectoryHandle | null
  const above = top === "/" ? "" : top.slice(0, top.lastIndexOf("/")) || "/"
  ovvi.controls.set("root", { value: top })
  /** A typed path, or the folder Choose Folder… picks (no path: the field's folder button): the tree rooted there,
   *  as the card's next place. A path that is no folder shakes the field. */
  const move = async (path?: string) => {
    const root = path ?? (await ovvi.pick.folder(top))
    if (!root) return
    if (!(await ovvi.files.info(root).then((info) => info.folder, () => false))) {
      return ovvi.controls.set("root", { refused: true })
    }
    ovvi.card.go(root === "/" ? "/" : `${root}/`)
  }
  /** Hidden files show: row 2's eye as the card has it, else the setting. Git's ignored files dim with the setting. */
  let dotfiles = own(ovvi).hiddenFiles ?? ovvi.settings.get<boolean>("hidden-files")
  let dim = ovvi.settings.get<boolean>("ignored")
  ovvi.controls.set("hidden-files", { value: dotfiles })

  /** Each folder's entries as the tree has them: `""` is the root, and a folder's path ends in `/`, as the tree's. */
  const children = new Map<string, Set<string>>()
  /** Folders in the tree that no listing filled yet: closed ones, and those of the filter's paths. */
  const unlisted = new Set<string>()
  const ignored = new Set<string>()
  let changes: Change[] = []
  /** The find bar's filter, every path of the root that it searches (loaded at its first letter), and how many match. */
  let filter = ""
  let paths: Promise<void> | undefined
  let matched = 0
  /** The root's last listing failed. */
  let failed = false

  /** The repository the root is in, and whether git's letters show: the root is that repository's root. Asked with
   *  each listing of the root, so a `git init` in the tree shows git's letters and the status bar. */
  let repo: string | null = null
  let repository = false
  const rooted = () => ovvi.git.root(top).catch(() => null)

  root.innerHTML = `<div id="find" class="find" hidden><div class="find-row"><input class="find-field" placeholder="Filter"
    aria-label="Filter" spellcheck="false"><span class="find-count"></span><button class="find-icon" aria-label="Close Filter"
    title="Close"></button></div></div><div id="message" hidden><span
    class="symbol"></span><p></p></div><div id="tree"></div><div id="matches" hidden></div><footer hidden></footer>`
  const renaming = (own: () => FileTree) => ({
    canRename: (item: { path: string }) => item.path !== UP.slice(0, -1),
    onRename: (event: FileTreeRenameEvent) => void renamed(event, own()),
    // A name in use in the tree, empty, or with a `/`: the row keeps its name.
    onError: (error: string) => void ovvi.toast(error),
  })
  const tree = new FileTree({ paths: above ? [UP] : [], ...look, renaming: renaming(() => tree) })
  const results = new FileTree({ paths: [], ...look, renaming: renaming(() => results) })
  const host = root.querySelector<HTMLElement>("#tree")!
  const message = root.querySelector<HTMLElement>("#message")!
  const matches = root.querySelector<HTMLElement>("#matches")!
  const find = root.querySelector<HTMLElement>("#find")!
  const field = find.querySelector("input")!
  const count = find.querySelector<HTMLElement>(".find-count")!
  const bar = root.querySelector("footer")!, status = footer(ovvi, bar, () => void run(git))
  tree.render({ containerWrapper: host })
  results.render({ containerWrapper: matches })
  for (const each of [tree, results]) stack(each.getFileTreeContainer()!)
  // pierre counts an ignored path as a change of the folders above it: their dot shows only for git's changes.
  // ponytail: a style per tree in its shadow root; drop it when pierre leaves ignored paths out of its counts.
  const dots = [tree, results].map((each) => each.getFileTreeContainer()!.shadowRoot!.appendChild(document.createElement("style")))
  keep(() => {
    tree.cleanUp()
    results.cleanUp()
  })
  /** The focus ring shows from an arrow key on, and goes with a click, as `:focus-visible` does. */
  const ring = (on: boolean) => {
    root.toggleAttribute("data-keys", on)
    for (const each of [tree, results]) each.getFileTreeContainer()?.toggleAttribute("data-keys", on)
  }
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
   *  the repository the root is in (the first listing). */
  async function list(at: string, rooted?: Promise<string | null>) {
    unlisted.delete(at)
    let entries: { name: string; folder: boolean; ignored: boolean }[]
    try {
      entries = await ovvi.files.list(at ? `${base}/${at.slice(0, -1)}` : top)
    } catch {
      if (at) return
      children.clear()
      unlisted.clear()
      ignored.clear()
      tree.resetPaths(above ? [UP] : [])
      failed = true
      show()
      return
    } finally {
      if (rooted) {
        repo = await rooted
        repository = repo === top
      }
    }
    if (!at) failed = false
    // An empty folder too: a refresh lists it again.
    if (!children.has(at)) children.set(at, new Set())
    const hidden = dotfiles ? 0 : entries.filter((entry) => entry.name.startsWith(".")).length
    if (!dotfiles) entries = entries.filter((entry) => !entry.name.startsWith("."))
    if (!at) status.folder(entries.filter((entry) => entry.folder).length, entries.filter((entry) => !entry.folder).length, hidden)
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
    // A root that cannot be listed has no counts.
    bar.hidden = failed
    message.querySelector("p")!.textContent = failed ? `Can't list ${top}`
      : none ? "No matching files" : empty ? "This folder is empty" : ""
    const icon = failed ? "folder.badge.questionmark" : empty ? "folder" : "magnifyingglass"
    if (!message.hidden && message.dataset.icon !== icon) {
      message.dataset.icon = icon
      void ovvi.symbol(icon, 30).then((url) => message.style.setProperty("--symbol", `url(${url})`), () => {})
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
    count.textContent = filter ? String(matched) : ""
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
    const letters = repository ? changes : []
    const status = [
      ...letters.flatMap(({ letter, path }) => (STATUS[letter] ? [{ path, status: STATUS[letter] }] : [])),
      ...(dim ? [...ignored] : []).map((path) => ({ path, status: "ignored" as const })),
    ]
    tree.setGitStatus(status)
    results.setGitStatus(status)
    const changed = [...new Set(letters.flatMap((change) => folders(change.path)))]
    // As specific as the rule that hides them, and after it: it wins.
    const shown = changed.map((path) =>
      `[data-item-path="${CSS.escape(path)}"]:not([data-item-git-status]) > [data-item-section="git"]`)
    const css = `[data-item-contains-git-change]:not([data-item-git-status]) > [data-item-section="git"] {
      visibility: hidden; }
      ${shown.length ? `${shown.join(", ")} { visibility: visible; }` : ""}`
    // Only on a change: a new style restyles the whole tree, and an agent's edits refresh it often.
    for (const style of dots) if (style.textContent !== css) style.textContent = css
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

  /** The repository's changes and its branch from git: the root's letters, when it is the repository's root, and
   *  the status bar's part, with the lines added and removed since HEAD (none before the first commit). The plumbing
   *  `diff-index` never writes the index, so it leaves no `index.lock` in an agent's way.
   *  ponytail: `--numstat` leaves untracked files out; count them too if the bar should match Git's diff. */
  async function git() {
    const at = repo
    const [now, head, numstat] = at ? await Promise.all([ovvi.git.status(at).catch(() => []),
      ovvi.git.head(at).catch(() => null), ovvi.run(["git", "--no-optional-locks", "diff-index", "--numstat", "HEAD"], { cwd: at }).catch(() => null)])
      : [[], null, null]
    changes = now
    showStatus()
    const lines = { added: 0, removed: 0 }
    // Binary files count `-`.
    for (const [plus, minus] of (numstat?.code === 0 ? numstat.stdout : "").split("\n").map((line) => line.split("\t"))) {
      lines.added += Number(plus) || 0
      lines.removed += Number(minus) || 0
    }
    status.repo(at, head, lines)
  }

  /** A row's rename (Return, as in the Finder) on the machine. The tree moved its row already, and moves it back when
   *  the rename fails; the other tree and the folders' entries follow it. */
  async function renamed(event: FileTreeRenameEvent, own: FileTree) {
    const slash = event.isFolder ? "/" : "", from = event.sourcePath + slash, to = event.destinationPath + slash
    rekey(from, to)
    const other = own === tree ? results : tree
    if (other.getItem(from)) other.move(from, to)
    try {
      await ovvi.files.move(`${base}/${event.sourcePath}`, `${base}/${event.destinationPath}`)
    } catch (error) {
      rekey(to, from)
      for (const each of [tree, results]) if (each.getItem(to)) each.move(to, from)
      void ovvi.toast(String((error as Error).message ?? error))
    }
  }

  /** A rename in the folders' entries: the path, and for a folder every path in it. */
  function rekey(from: string, to: string) {
    const swap = (path: string) =>
      path === from || (from.endsWith("/") && path.startsWith(from)) ? to + path.slice(from.length) : path
    for (const [at, set] of [...children]) {
      children.delete(at)
      children.set(swap(at), new Set([...set].map(swap)))
    }
    for (const set of [unlisted, ignored]) {
      for (const path of [...set]) set.delete(path) && set.add(swap(path))
    }
  }

  /** A path under the root (absolute, as the app sends it) shown: its folders listed and open, its row selected, in the
   *  middle of the card, or only scrolled into view (`nearest`). */
  async function reveal(path: string, offset?: "nearest") {
    if (!path.startsWith(`${base}/`)) return
    const relative = path.slice(base.length + 1)
    // A dotfile shows only with the hidden files: the eye turns on (Show in File Explorer on `.gitignore`).
    if (!dotfiles && dotted(relative)) {
      dotfiles = true
      choose(ovvi, { hiddenFiles: true })
      ovvi.controls.set("hidden-files", { value: true })
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

  ovvi.on("control", ({ id, value }) => {
    // A click on row 2 leaves the tree with no selection.
    clear()
    if (id === "filter") {
      if (value === true) openFind()
      else closeFind()
    } else if (id === "collapse") {
      for (const at of children.keys()) if (at) folder(at)?.collapse()
    } else if (id === "root") {
      void move(value === undefined ? undefined : String(value))
    } else if (id === "hidden-files") {
      choose(ovvi, { hiddenFiles: value === true })
      showDotfiles(value === true)
    }
  })
  // A new setting: the eye follows it unless the card has its own choice.
  ovvi.on("settings", (changed) => {
    if ("ignored" in changed) {
      dim = changed.ignored === true
      showStatus()
    }
    if ("hidden-files" in changed && own(ovvi).hiddenFiles === undefined) {
      const yes = changed["hidden-files"] === true
      ovvi.controls.set("hidden-files", { value: yes })
      showDotfiles(yes)
    }
  })

  function showDotfiles(yes: boolean) {
    dotfiles = yes
    run(refresh).catch(console.error)
    // The filter's paths again, with the dotfiles or without.
    paths = filter ? run(loadPaths).catch(() => {}) : undefined
    void (paths ?? queue).then(match).catch(console.error)
  }
  ovvi.on("find", () => openFind())

  /** The find bar at the top right (row 2's Filter, ⌘F, or a letter typed in the tree) takes the keyboard; `text` in
   *  place of its text. */
  function openFind(text?: string) {
    find.hidden = false
    ovvi.controls.set("filter", { value: true })
    if (text !== undefined) {
      field.value = text
      filtered()
    } else {
      field.select()
    }
    field.focus()
  }

  /** Esc, its close button or row 2's Filter again: the bar goes, with its filter, and the tree takes the keyboard. */
  function closeFind() {
    find.hidden = true
    ovvi.controls.set("filter", { value: false })
    if (field.value) {
      field.value = ""
      filtered()
    }
    take()
  }

  function filtered() {
    filter = field.value
    paths ??= filter ? run(loadPaths).catch(() => {}) : undefined
    void (paths ?? queue).then(match).catch(console.error)
  }
  field.oninput = filtered
  // Esc closes the bar; Return and ↓ go to the matches.
  field.onkeydown = (event) => {
    if (event.key === "Escape") closeFind()
    else if (event.key === "Enter" || event.key === "ArrowDown") take()
    else return
    event.preventDefault()
  }
  const close = find.querySelector("button")!
  close.onclick = closeFind
  symbols(ovvi, ["xmark"])
  close.style.setProperty("--symbol", "var(--sf-xmark)")

  // After each change under the root, and once when the card shows again.
  ovvi.files.watch(top, () => {
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
    for (const path of await ovvi.files.paths(top).catch(() => [])) {
      if (dotfiles || !dotted(path)) put(path, operations)
    }
    tree.batch(operations)
  }

  /** The row's id in the tree, the place it opens (`..`: the parent folder) and whether it is a folder's. */
  const row = (event: Event) => {
    const node = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && Boolean(n.dataset.itemPath))
    const id = node?.dataset.itemPath
    return id === undefined ? undefined : { id, arg: arg(id), folder: node!.dataset.itemType === "folder" }
  }
  const arg = (id: string) => id === UP ? (above === "/" ? "/" : `${above}/`) : `${base}/${id}`
  /** The click is on a folder's chevron, at the left of its icon. */
  const chevron = (event: MouseEvent) => {
    const icon = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && n.dataset.itemSection === "icon")
    const right = icon?.querySelector("svg")?.getBoundingClientRect().right
    return right !== undefined && event.clientX <= right
  }

  for (const trees of [host, matches]) {
    // A file: double-click in the card, ⌘-click in a new tab, ⌥-click to the side; a folder the same way as the root.
    // As in the Finder, a click on a folder's name only selects it: its chevron and → open it, so a double-click never
    // shows it open first, and a click on no row clears the selection. In the capture phase, before the tree's own
    // click (⌘ adds to its selection, a click toggles a folder).
    trees.addEventListener(
      "click",
      (event) => {
        const at = row(event)
        if (!at) return clear()
        // A ⌘- or ⌥-double-click opens once.
        if (event.detail > 1 && (event.metaKey || event.altKey)) return event.stopPropagation()
        const toggle = at.folder && chevron(event)
        // VoiceOver's press on `..` (no clicks counted) goes up.
        if (event.metaKey || event.altKey || (event.detail >= 2 && !toggle) || (at.id === UP && !event.detail)) {
          event.stopPropagation()
          open(ovvi, at.arg, how(event))
        } else if (at.folder && !toggle && event.detail === 1 && !event.shiftKey && !event.ctrlKey) {
          event.stopPropagation()
          only(filter ? results : tree, at.id)
          take(at.id)
        }
      },
      true,
    )
    trees.addEventListener("keydown", keys, true)
    // The app's menu: Open (Open as Root on a folder), Open in New Tab, Open to the Side, Rename (not on `..`).
    trees.addEventListener("contextmenu", (event) => {
      // The rename's field has its own.
      if (event.composedPath()[0] instanceof HTMLInputElement) return
      const at = row(event)
      if (!at) return event.preventDefault()
      const shown = filter ? results : tree
      void menu(ovvi, event, at.arg, { rename: at.id === UP ? undefined : () => shown.startRenaming(at.id) && stem(shown, at.id) })
    })
  }

  /** The tree's keys, as the Finder's list has them, before the tree's own: Return renames the selected row, ⌘O and
   *  ⌘↓ open it, ⌘↑ goes to the parent folder, a letter filters, Space does nothing (Quick Look's key: no preview card
   *  here). The first ↓ or ↑ before a key moved the keyboard goes to the first or last row, not one past the row
   *  nobody sees. ↑↓→← are the tree's. */
  function keys(event: KeyboardEvent) {
    // The rename's field has its own.
    if (event.composedPath()[0] instanceof HTMLInputElement) return
    const shown = filter ? results : tree, key = event.key
    const plain = !event.shiftKey && !event.metaKey && !event.altKey && !event.ctrlKey
    const command = event.metaKey && !event.shiftKey && !event.altKey && !event.ctrlKey
    const moved = root.hasAttribute("data-keys"), selected = shown.getSelectedPaths().length > 0
    // The row the user sees: selected, or with the ring.
    const at = moved || selected ? shown.getFocusedPath() : null
    if (key.startsWith("Arrow")) ring(true)
    if (plain && key === "Enter") {
      if (at && shown.startRenaming(at)) stem(shown, at)
    } else if (command && (key === "o" || key === "ArrowDown")) {
      if (at) open(ovvi, arg(at), "card")
    } else if (command && key === "ArrowUp") {
      if (above) ovvi.card.go(arg(UP))
    } else if (plain && key === "Escape" && !find.hidden) {
      closeFind()
    } else if (key.length === 1 && key !== " " && !event.metaKey && !event.ctrlKey && !event.altKey) {
      openFind(filter + key)
    } else if (plain && (key === "ArrowDown" || key === "ArrowUp") && !moved && !selected) {
      if (key === "ArrowUp") shown.focusLastItem()
      else shown.focusFirstItem()
    } else if (!(plain && key === " ")) {
      return
    }
    event.preventDefault()
    event.stopPropagation()
  }

  /** A file's rename starts with its name selected but its extension, as in the Finder: once the tree selected the
   *  whole name, a frame later. */
  function stem(shown: FileTree, at: string) {
    requestAnimationFrame(() => {
      const field = shown.getFileTreeContainer()?.shadowRoot?.querySelector<HTMLInputElement>("[data-item-rename-input]")
      const dot = field?.value.lastIndexOf(".") ?? 0
      if (field && dot > 0 && !at.endsWith("/")) field.setSelectionRange(0, dot)
    })
  }

  /** No row selected, in either tree. */
  function clear() {
    for (const each of [tree, results]) for (const at of each.getSelectedPaths()) each.getItem(at)?.deselect()
  }

  /** The row alone selected: a kept tree still has the row it opened before. */
  function only(shown: FileTree, path: string) {
    clear()
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
  // the keyboard keeps it (else the tree scrolls to its old row between the press and the release). The find bar
  // keeps it while it has it.
  const given = () => requestAnimationFrame(() => {
    if (place.shown() && document.activeElement !== field
      && !(filter ? results : tree).getFileTreeContainer()?.shadowRoot?.activeElement) {
      take()
    }
  })
  addEventListener("focus", given)
  keep(() => removeEventListener("focus", given))

  // The repository the root is in with the first listing, so it dims what git ignores (one wait for both, as each
  // starts a process); a landing's row before the tree shows; then git's letters and the status bar.
  await run(() => list("", rooted()))
  if (place.at) await run(() => reveal(place.at!))
  run(git)
  // Back on the kept tree: the row it came back from, scrolled into view only when it is out of it.
  return (at) => void run(() => reveal(at, "nearest"))
}
