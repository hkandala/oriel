// A Git card's diff, a page of its own (`oriel.pages`): a source's patch in @pierre/diffs' CodeView, one scroll with a
// sticky header per file, and the file list beside it; a commit's subject, body and facts above its files. Row 2 has
// Git Home, the layout, the wrap, the list and previous / next change.
import type { Page } from "@oriel/plugin-api"
import {
  CodeView,
  type CodeViewDiffItem,
  type CodeViewOptions,
  type FileDiffMetadata,
  parsePatchFiles,
} from "@pierre/diffs"
import { element, failed as toast, fileIcon, home, type How, how, keep, nameAndFolder, open, oriel } from "./lib"

const letters = { change: "M", "rename-pure": "R", "rename-changed": "R", new: "A", deleted: "D" }
/**
 * A file's header controls, made once per file diff (`draw` keeps an unchanged file's) for CodeView and once for the copy
 * on top (`stuck`): pierre asks for them at every render of the file (a scroll, the highlighter's answer), and a click
 * whose press and release land on two different nodes does nothing.
 */
const headers = new WeakMap<FileDiffMetadata, HTMLElement>()
const tops = new WeakMap<FileDiffMetadata, HTMLElement>()
function header(diff: FileDiffMetadata, make: (diff: FileDiffMetadata) => HTMLElement, cache = headers) {
  const node = cache.get(diff) ?? make(diff)
  cache.set(diff, node)
  return node
}

/** "3 hours ago", "yesterday", "in 2 days": the nearest unit. */
function ago(date: Date) {
  const seconds = (date.getTime() - Date.now()) / 1000
  const units: [Intl.RelativeTimeFormatUnit, number][] = [["year", 31536000], ["month", 2592000], ["week", 604800],
    ["day", 86400], ["hour", 3600], ["minute", 60]]
  const [unit, size] = units.find(([, size]) => Math.abs(seconds) >= size) ?? ["second", 1]
  return new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(Math.round(seconds / size), unit)
}

function sums(file: FileDiffMetadata) {
  let added = 0
  let removed = 0
  for (const hunk of file.hunks) {
    added += hunk.additionLines
    removed += hunk.deletionLines
  }
  return { added, removed }
}

/** `+n −m`, as the spec writes them (the header's own counts are hidden). */
function counts(file: FileDiffMetadata) {
  const { added, removed } = sums(file)
  return [
    element("span", "added", added ? `+${added}` : ""),
    element("span", "removed", removed ? `−${removed}` : ""),
  ]
}

function letter(file: FileDiffMetadata) {
  return element("span", `letter ${letters[file.type]}`, letters[file.type])
}

function blocks(file: FileDiffMetadata) {
  return file.hunks.flatMap((hunk) => {
    let line = hunk.additionStart
    let old = hunk.deletionStart
    return hunk.hunkContent.flatMap((content) => {
      if (content.type === "context") {
        line += content.lines
        old += content.lines
        return []
      }
      const place = content.additions
        ? { id: file.name, lineNumber: line, side: "additions" as const }
        : { id: file.name, lineNumber: old, side: "deletions" as const }
      line += content.additions
      old += content.deletions
      return [place]
    })
  })
}

/** The new file's line for an old one shown: the same line when unchanged, the one after the change when removed. */
function newLine(file: FileDiffMetadata, number: number) {
  for (const hunk of file.hunks) {
    let line = hunk.additionStart
    let old = hunk.deletionStart
    for (const content of hunk.hunkContent) {
      const context = content.type === "context"
      const span = context ? content.lines : content.deletions
      if (number >= old && number < old + span) return context ? line + number - old : line + content.additions
      line += context ? content.lines : content.additions
      old += span
    }
  }
}

function text(file: FileDiffMetadata) {
  return `${file.deletionLines.join("")}\0${file.additionLines.join("")}`
}

/** The diff of a source of a root in its page, drawn once read, at a file (`at`) when it has it. A first read that fails
 *  (a folder not yet a repository, a machine away) shows git's error and reads again at the next change in the work
 *  tree. Its header controls, handlers and watch are the page's own (`place.oriel`). */
export async function make(place: Page, root: string, source: string) {
  const api = place.oriel
  const page = element("div")
  page.id = "diff"
  // The file list slides in and out as every plugin's sidebar (card.css).
  const nav = element("nav", "list oriel-sidebar")
  const main = element("main", "diff")
  /** git's message when the first read failed. */
  const failure = element("p", "failure")
  /** No changes: the home's placeholder, in the middle; the file list gives way. */
  const clean = element("div", "placeholder")
  clean.hidden = true
  clean.innerHTML = `<span class="symbol" style="--symbol: var(--sf-checkmark-circle)"></span><h2>No changes</h2>`
  /** A commit's subject, body and facts, at the top of the scroll; empty for the working tree. */
  const about = element("header", "about")
  page.append(nav, main, failure, clean)
  place.element.append(page)

  /** The patch drawn, "" before the first; a failed read is undefined. */
  let patch: string | undefined
  let files: FileDiffMetadata[] = []
  // Each change block's first line, in order, for previous / next; the last one stepped to, or half a step before
  // the next one after a pick in the list.
  let changes: { id: string; lineNumber: number; side: "additions" | "deletions" }[] = []
  let change = -1
  /** The files marked Viewed, with their text then: a file that changes since drops the mark. */
  const viewed = new Map<string, string>()
  // Side by Side and the wrap as the header has them, then the page's own; the file list as the card keeps it.
  let split = api.controls.get("diff.layout") === "split"
  let wrap = api.controls.get("diff.wrap") === true
  let list = oriel.state.get<{ list?: boolean }>()?.list ?? true
  nav.toggleAttribute("data-closed", !list)

  const options: CodeViewOptions<undefined, undefined> = {
    theme: { dark: "pierre-dark", light: "pierre-light" },
    themeType: oriel.theme.dark ? "dark" : "light",
    diffStyle: split ? "split" : "unified",
    overflow: overflow(),
    lineDiffType: "word",
    // `N unmodified lines`, not expandable: that needs each file's whole text.
    hunkSeparators: "line-info-basic",
    stickyHeaders: true,
    // Clicks right after Next Change or a pick in the list (CodeView drops them while it scrolls).
    pointerEventsOnScroll: true,
    layout: { paddingTop: 0, paddingBottom: 24, gap: 0 },
    // The file header's row (`.file` in diff.css).
    itemMetrics: { diffHeaderHeight: 32 },
    // The card's fill shows through; the sticky header is opaque in the card's color, with a line under it.
    unsafeCSS: `
      :host {
        --diffs-light-bg: transparent !important;
        --diffs-dark-bg: transparent !important;
        --diffs-addition-color-override: var(--finished);
        --diffs-deletion-color-override: var(--error);
        --diffs-modified-color-override: var(--working);
        --diffs-bg-separator-override: transparent;
      }
      [data-line-type=change-addition] {
        --diffs-computed-diff-line-bg: color-mix(in srgb, var(--finished) 10%, transparent) !important;
      }
      [data-line-type=change-deletion] {
        --diffs-computed-diff-line-bg: color-mix(in srgb, var(--error) 10%, transparent) !important;
      }
      [data-line-type=change-addition] [data-diff-span] {
        background-color: color-mix(in srgb, var(--finished) 28%, transparent) !important;
      }
      [data-line-type=change-deletion] [data-diff-span] {
        background-color: color-mix(in srgb, var(--error) 28%, transparent) !important;
      }
      [data-separator] { border-block: 0.5px solid var(--divider) }
      [data-separator-content] { background: none !important; color: var(--dim) }
      [data-diffs-header] { height: 32px; background: var(--card); cursor: default; }`,
    renderCodeViewHeader: () => about,
    // The file's own row, as the card's rows: the disclosure, its icon, name and folder, its counts and letter, then
    // Viewed and Open File. A diff item's file is its diff.
    renderCustomHeader: (file) => fresh(header(file as FileDiffMetadata, fileRow), file as FileDiffMetadata),
    // ⌘-click: the file at the line in a new tab (⌥-click: to the side), or for a removed line at the one after it.
    onLineClick: (line, context) => {
      const { event, lineNumber } = line, file = files.find((file) => file.name === context.item.id)
      if ((event.metaKey || event.altKey) && file && file.type !== "deleted") {
        const added = "annotationSide" in line && line.annotationSide === "additions"
        openFile(file.name, added ? lineNumber : newLine(file, lineNumber), how(event))
      }
    },
  }
  function fileRow(diff: FileDiffMetadata) {
    const row = element("div", "file"), disclosure = element("button", "disclosure", "›")
    disclosure.ariaLabel = "Show or hide the file"
    disclosure.onclick = () => collapse(diff.name, !item(diff.name).collapsed)
    const [base, dir] = nameAndFolder(diff.name)
    const name = element("span", "name", base)
    // A rename names its old path in the folder's place.
    const folder = element("span", "folder", diff.prevName && diff.prevName !== diff.name ? `from ${diff.prevName}` : dir)
    row.title = diff.name
    row.append(disclosure, fileIcon(diff.name), name, folder, ...counts(diff), letter(diff), actions(diff))
    return row
  }

  /** A file's header row with its fold and Viewed as they are now. */
  function fresh(node: HTMLElement, diff: FileDiffMetadata) {
    node.querySelector(".disclosure")!.classList.toggle("shut", Boolean(item(diff.name)?.collapsed))
    node.querySelector("input")!.checked = viewed.has(diff.name)
    return node
  }

  /** Viewed, and Open File but on a deleted file. */
  function actions(diff: FileDiffMetadata) {
    const box = element("span", "actions"), label = element("label", "mark")
    const check = element("input", "")
    check.type = "checkbox"
    check.ariaLabel = `Viewed ${diff.name}`
    check.checked = viewed.has(diff.name)
    check.onchange = () => {
      if (check.checked) viewed.set(diff.name, text(diff))
      else viewed.delete(diff.name)
      collapse(diff.name, check.checked)
      row(diff.name)?.classList.toggle("viewed", check.checked)
    }
    label.append(check, "Viewed")
    box.append(label)
    // A deleted file has nothing to open.
    if (diff.type !== "deleted") {
      const open = element("button", "open", "Open File")
      open.ariaLabel = `Open ${diff.name}`
      open.onclick = (event) => openFile(diff.name, undefined, how(event))
      box.append(open)
    }
    return box
  }

  // A copy: CodeView compares each `setOptions` with the object it holds, which must not change under it.
  const viewer = new CodeView({ ...options })
  viewer.setup(main)
  place.keep(() => viewer.cleanUp())

  /**
   * A copy of the header of the file at the top, sticky in the diff's scroll after a commit's facts, so the compositor
   * keeps it in place: CodeView draws only the lines near the view, in a box it moves from script, and a fast scroll
   * outran it, so the file's own header went blank with the lines. The file's own header covers this one whenever it
   * is drawn (also while the next file's pushes it up); a scroll only changes which file this one names. Inert: the
   * file's own header has the controls.
   */
  const stuck = element("div", "stuck")
  stuck.inert = true
  stuck.hidden = true
  place.keep(viewer.subscribeToScroll(stick))
  // CodeView puts the facts' box in once its highlighter is ready, which can come after the files.
  const resized = new ResizeObserver(() => stick())
  resized.observe(about)
  place.keep(() => resized.disconnect())

  /** Names the last file whose top is at or above the view's; the first when the view is above them all. After new
   *  files, on the next frame: CodeView lays them out on it, asked first. */
  function stick() {
    // After the facts' box, which CodeView makes on its first render.
    const host = viewer.getHeaderElement()
    if (host && stuck.previousElementSibling !== host) host.after(stuck)
    const top = viewer.getScrollTop()
    let low = 0, high = files.length - 1
    while (low < high) {
      const middle = (low + high + 1) >> 1
      if ((viewer.getTopForItem(files[middle].name) ?? 0) <= top) low = middle
      else high = middle - 1
    }
    const file = files[low]
    stuck.hidden = !file
    if (!file) return
    const node = fresh(header(file, fileRow, tops), file)
    if (stuck.firstChild !== node) stuck.replaceChildren(node)
  }

  /** A commit's subject (also the card's title), its body, and its author, date, hash and parents; none for the working
   *  tree. */
  function describe(facts: Awaited<ReturnType<typeof oriel.git.show>> | undefined) {
    about.replaceChildren()
    document.title = facts?.subject ?? ""
    if (!facts) return
    const date = new Date(facts.date), list = element("dl")
    const fact = (term: string, ...value: (Node | string)[]) => {
      const line = element("dd")
      line.append(...value)
      list.append(element("dt", "", term), line)
    }
    fact("Author", facts.author, element("span", "dim", ` <${facts.email}>`))
    fact("Date", ago(date), element("span", "dim", ` · ${date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })}`))
    const copy = element("button", "hash", facts.hash.slice(0, 10))
    copy.title = "Copy"
    copy.ariaLabel = `Copy ${facts.hash}`
    copy.onclick = () => oriel.clipboard.write(facts.hash).then(() => {
      copy.textContent = "Copied"
      setTimeout(() => (copy.textContent = facts.hash.slice(0, 10)), 1200)
    }, toast)
    fact("Commit", copy)
    if (facts.parents.length) {
      fact(facts.parents.length > 1 ? "Parents" : "Parent", ...facts.parents.map((parent) => {
        const button = element("button", "hash", parent.slice(0, 10))
        button.ariaLabel = `Parent ${parent}`
        button.onclick = (event) => open(`${home(root)} ${parent}`, { how: how(event), plugin: "git" })
        return button
      }))
    }
    about.append(element("h1", "", facts.subject), ...(facts.body ? [element("p", "body", facts.body)] : []), list)
  }

  /**
   * Draws a new patch. A file keeps its place, its fold and its Viewed while its text is the same, and draws nothing new:
   * CodeView draws a kept item again only for a new `version`. A Viewed file that changed opens again. A file new to the
   * card with over 2,000 changed lines starts folded.
   */
  function draw(next: string) {
    patch = next
    files = parsePatchFiles(patch).flatMap((parsed) => parsed.files)
      .map((file) => {
        const was = item(file.name)?.fileDiff
        return was && text(was) === text(file) && was.type === file.type && was.prevName === file.prevName ? was : file
      })
    const changed = new Set<string>()
    for (const [name, was] of viewed) {
      const file = files.find((file) => file.name === name)
      if (!file || text(file) !== was) {
        viewed.delete(name)
        changed.add(name)
      }
    }
    viewer.setItems(files.map((fileDiff) => {
      const { added, removed } = sums(fileDiff), was = item(fileDiff.name)
      const folded = was ? was.collapsed && !changed.has(fileDiff.name) : added + removed > 2000
      const collapsed = viewed.has(fileDiff.name) || folded
      // The same file folded the same: the same version, so nothing draws.
      const version = was && (was.fileDiff !== fileDiff || was.collapsed !== collapsed) ? (was.version ?? 0) + 1 : was?.version
      return { id: fileDiff.name, type: "diff", fileDiff, collapsed, version }
    }))
    changes = files.flatMap(blocks)
    shown()
    // As the Git home's lists: a title, its count after it.
    const title = element("header", "title")
    title.append(element("h2", "", "Files"), element("span", "count", files.length ? String(files.length) : ""))
    nav.replaceChildren(title)
    for (const file of files) {
      const button = element("button", viewed.has(file.name) ? "row viewed" : "row")
      button.dataset.id = file.name
      const [name, folder] = nameAndFolder(file.name)
      button.append(
        fileIcon(file.name),
        element("span", "name", name),
        element("span", "folder", folder),
        ...counts(file),
        letter(file),
      )
      button.title = file.name
      button.ariaLabel = file.name
      button.onclick = () => reveal(file.name)
      nav.append(button)
    }
  }

  /** The file list and its button only with files to list; No changes when a read found none. */
  function shown() {
    nav.hidden = !files.length
    clean.hidden = Boolean(files.length) || patch === undefined
    api.controls.set("diff.file-list", { enabled: files.length > 0 })
    requestAnimationFrame(stick)
  }

  function openFile(name: string, line: number | undefined, how: How) {
    open(`${root}/${name}`, { how, at: line ? String(line) : undefined })
  }

  /** Another layout or width gives the lines other heights: back to the change last stepped to, not wherever the old
   * offset now falls. */
  function keepChange() {
    if (changes[change]) viewer.scrollTo({ type: "line", ...changes[change], align: "center" })
  }

  function item(id: string) {
    return viewer.getItem(id) as CodeViewDiffItem<undefined>
  }

  function collapse(id: string, collapsed: boolean) {
    const old = item(id)
    viewer.updateItem({ ...old, collapsed, version: (old.version ?? 0) + 1 })
  }

  function row(id: string) {
    return [...nav.children].find((node) => (node as HTMLElement).dataset.id === id)
  }

  function reveal(id: string) {
    if (item(id).collapsed) collapse(id, false)
    viewer.scrollTo({ type: "item", id, align: "start" })
    const order = (name: string) => files.findIndex((file) => file.name === name)
    const next = changes.findIndex((block) => order(block.id) >= order(id))
    change = (next < 0 ? changes.length : next) - 0.5
  }

  api.on("theme", (theme) => {
    options.themeType = theme.dark ? "dark" : "light"
    viewer.setOptions({ ...options })
  })

  // One patch at a time; a change during one asks again after it.
  let asking: Promise<void> | undefined
  let again = false

  /** The patch again, drawn only when its text changed: Working Tree follows the work tree. */
  async function refresh() {
    if (asking) {
      again = true
      return asking
    }
    // A read that throws ends here too: the next change reads again.
    asking = (async () => {
      try {
        do {
          again = false
          apply(await read())
        } while (again)
      } finally {
        asking = undefined
      }
    })()
    return asking
  }

  const read = () => oriel.git.diff(root, source).catch((error: Error) => error)

  /** A patch drawn when its text changed. A diff drawn keeps its patch on a failed read; a first read shows why. */
  function apply(next: string | Error) {
    if (!(next instanceof Error)) {
      if (next !== patch) draw(next)
    } else if (patch === undefined) failure.textContent = next.message
  }

  /** Side by Side wraps each column's lines: a line scrolled past its narrow column was cut off where a click lands.
   *  Unified wraps with Word Wrap. */
  function overflow() {
    return split || wrap ? "wrap" : "scroll"
  }

  function layout(next: { split?: boolean; wrap?: boolean }) {
    split = next.split ?? split
    wrap = next.wrap ?? wrap
    // Side by Side always wraps.
    api.controls.set("diff.wrap", { enabled: !split })
    options.diffStyle = split ? "split" : "unified"
    options.overflow = overflow()
    viewer.setOptions({ ...options })
    keepChange()
  }

  function toggleList() {
    list = !list
    nav.toggleAttribute("data-closed", !list)
    keep({ list })
    api.controls.set("diff.file-list", { title: list ? "Hide File List" : "Show File List" })
    // Once the viewer has its new width: Side by Side wraps lines to it. With Reduce Motion there is no slide.
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) requestAnimationFrame(() => requestAnimationFrame(keepChange))
  }
  // After the slide: once, not for each of its properties.
  nav.addEventListener("transitionend", (event) => event.target === nav && event.propertyName === "visibility" && keepChange())

  function step(by: 1 | -1) {
    if (!changes.length) return
    const next = by > 0 ? Math.floor(change) + 1 : Math.ceil(change) - 1
    change = Math.min(Math.max(next, 0), changes.length - 1)
    const block = changes[change]
    if (item(block.id).collapsed) collapse(block.id, false)
    viewer.scrollTo({ type: "line", ...block, align: "center" })
  }

  api.on("control", ({ id, value }) => {
    if (id === "diff.home") oriel.card.go(home(root))
    else if (id === "diff.layout") layout({ split: value === "split" })
    else if (id === "diff.wrap") layout({ wrap: value === true })
    else if (id === "diff.file-list") toggleList()
    else if (id === "diff.previous") step(-1)
    else if (id === "diff.next") step(1)
  })
  // While the page shows, the working tree asks for its patch again after each change under the root (and draws only
  // the files that changed), and a diff whose first read failed tries again; also once when it shows again.
  // A change while it draws calls once when it shows.
  api.files.watch(root, () => (source === "uncommitted" || patch === undefined) && void refresh())
  api.controls.set("diff.file-list", { title: list ? "Hide File List" : "Show File List" })
  api.controls.set("diff.wrap", { enabled: !split })
  // Read first, then draw all of it in one go: the page before (the home, or the diff a Parent leaves) stays until
  // then, with no blank page while git answers.
  const [next, facts] = await Promise.all([read(), source === "uncommitted"
    ? undefined
    : oriel.git.show(root, source).catch(() => undefined)])
  describe(facts)
  apply(next)
  if (place.at && files.some((file) => file.name === place.at)) reveal(place.at)
  // Back at this diff with a file (a change row of the home): a scroll to it.
  api.on("place", ({ at }) => at && files.some((file) => file.name === at) && reveal(at))
}
