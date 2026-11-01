// A Git card's diff: a source's patch in @pierre/diffs' CodeView, one scroll with a sticky header per file, and the
// file list beside it; a commit's subject, body and facts above its files. Row 2 has the layout, the wrap, the list and
// previous / next change (`main.ts`).
import {
  CodeView,
  type CodeViewDiffItem,
  type CodeViewOptions,
  type FileDiffMetadata,
  parsePatchFiles,
} from "@pierre/diffs"
import { control, element, failed as toast, home, type How, how, keep, nameAndFolder, open, oriel, symbol } from "./lib"

const letters = { change: "M", "rename-pure": "R", "rename-changed": "R", new: "A", deleted: "D" }
const page = element("div")
page.id = "diff"
page.hidden = true
// The file list slides in and out as every plugin's sidebar (card.css).
const nav = element("nav", "list oriel-sidebar")
const main = element("main", "diff")
const empty = element("p", "empty")
/** A commit's subject, body and facts, at the top of the scroll; empty for the working tree. */
const about = element("header", "about")
page.append(nav, main, empty)
document.body.append(page)

let root = ""
let source = ""
/** The patch drawn, "" before the first; a failed read is undefined. */
let patch: string | undefined
let files: FileDiffMetadata[] = []
// Each change block's first line, in order, for previous / next; the last one stepped to, or half a step before
// the next one after a pick in the list.
let changes: { id: string; lineNumber: number; side: "additions" | "deletions" }[] = []
let change = -1
/** The files marked Viewed, with their text then: a file that changes since drops the mark. */
const viewed = new Map<string, string>()
// Side by Side, the wrap and the file list, kept per card.
let split = oriel.controls.get("diff.layout") === "split"
let wrap = oriel.controls.get("diff.wrap") === true
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
  // The file header's band (`.file` in diff.css).
  itemMetrics: { diffHeaderHeight: 40 },
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
    [data-diffs-header] { height: 40px; background: var(--card); cursor: default; }`,
  renderCodeViewHeader: () => about,
  // The file's own row, as the card's rows: the disclosure, its icon, name and folder, its counts and letter, then
  // Viewed and Open File. A diff item's file is its diff.
  renderCustomHeader: (file) => {
    const diff = file as FileDiffMetadata
    const node = header(diff, (diff) => {
      const row = element("div", "file"), disclosure = element("button", "disclosure", "›")
      disclosure.ariaLabel = "Show or hide the file"
      disclosure.onclick = () => collapse(diff.name, !item(diff.name).collapsed)
      const [base, dir] = nameAndFolder(diff.name)
      const name = element("span", "name", base)
      // A rename names its old path in the folder's place.
      const folder = element("span", "folder", diff.prevName && diff.prevName !== diff.name ? `from ${diff.prevName}` : dir)
      row.title = diff.name
      row.append(disclosure, symbol("doc"), name, folder, ...counts(diff), letter(diff), actions(diff))
      return row
    })
    node.querySelector(".disclosure")!.classList.toggle("shut", Boolean(item(diff.name)?.collapsed))
    return node
  },
  // ⌘-click: the file at the line in a new tab (⌥-click: to the side), or for a removed line at the one after it.
  onLineClick: (line, context) => {
    const { event, lineNumber } = line, file = files.find((file) => file.name === context.item.id)
    if ((event.metaKey || event.altKey) && file && file.type !== "deleted") {
      const added = "annotationSide" in line && line.annotationSide === "additions"
      openFile(file.name, added ? lineNumber : newLine(file, lineNumber), how(event))
    }
  },
}
/**
 * A file's header controls, made once per file diff (`draw` keeps an unchanged file's): pierre asks for them at every
 * render of the file (a scroll, the highlighter's answer), and a click whose press and release land on two different
 * nodes does nothing.
 */
const headers = new WeakMap<FileDiffMetadata, HTMLElement>()
function header(diff: FileDiffMetadata, make: (diff: FileDiffMetadata) => HTMLElement) {
  const node = headers.get(diff) ?? make(diff)
  headers.set(diff, node)
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

/** Shows a source of a root, from its top, at a file (`at`) when it has it. A first read that fails (a folder not yet
 *  a repository, a machine away) shows git's error and reads again at the next change in the work tree. */
export async function show(nextRoot: string, nextSource: string, at?: string) {
  control("diff.file-list", { title: list ? "Hide File List" : "Show File List" })
  control("diff.wrap", { enabled: !split })
  // The diff shown, with a landing: only a scroll to the file.
  if (!page.hidden && page.style.visibility === "" && nextRoot === root && nextSource === source && patch !== undefined) {
    if (at && files.some((file) => file.name === at)) reveal(at)
    return true
  }
  root = nextRoot
  source = nextSource
  clear()
  // Drawn unseen over the place before, which stays until the patch drew: no blank page while git answers.
  page.style.visibility = "hidden"
  page.hidden = false
  await Promise.all([refresh(), commit()])
  // Not after another move meanwhile.
  if (root !== nextRoot || source !== nextSource) return false
  page.style.visibility = ""
  if (at && files.some((file) => file.name === at)) reveal(at)
  return true
}

/** The home shows: the diff lets go of its patch, as each place starts from its top. */
export const hide = () => {
  page.hidden = true
  page.style.visibility = ""
  root = source = ""
  clear()
  document.title = ""
}

/** A commit's subject (also the card's title), its body, and its author, date, hash and parents. */
async function commit() {
  const at = `${root} ${source}`
  about.replaceChildren()
  document.title = ""
  if (source === "uncommitted") return
  const facts = await oriel.git.show(root, source).catch(() => undefined)
  if (!facts || at !== `${root} ${source}`) return
  document.title = facts.subject
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

/** "3 hours ago", "yesterday", "in 2 days": the nearest unit. */
function ago(date: Date) {
  const seconds = (date.getTime() - Date.now()) / 1000
  const units: [Intl.RelativeTimeFormatUnit, number][] = [["year", 31536000], ["month", 2592000], ["week", 604800],
    ["day", 86400], ["hour", 3600], ["minute", 60]]
  const [unit, size] = units.find(([, size]) => Math.abs(seconds) >= size) ?? ["second", 1]
  return new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(Math.round(seconds / size), unit)
}

function clear() {
  patch = undefined
  files = []
  changes = []
  change = -1
  viewed.clear()
  viewer.setItems([])
  nav.replaceChildren()
  empty.textContent = ""
  main.scrollTop = 0
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
  empty.textContent = files.length ? "" : "No changes"
  // As the Git home's lists: a title, its count after it.
  const title = element("header", "title")
  title.append(element("h2", "", "Files"), element("span", "count", files.length ? String(files.length) : ""))
  nav.replaceChildren(title)
  for (const file of files) {
    const button = element("button", viewed.has(file.name) ? "row viewed" : "row")
    button.dataset.id = file.name
    const [name, folder] = nameAndFolder(file.name)
    button.append(
      symbol("doc"),
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
  const next = changes.findIndex((place) => order(place.id) >= order(id))
  change = (next < 0 ? changes.length : next) - 0.5
}

oriel.on("theme", (theme) => {
  options.themeType = theme.dark ? "dark" : "light"
  viewer.setOptions({ ...options })
})

// One patch at a time; a change during one asks again after it.
let asking: Promise<void> | undefined
let again = false

/** The patch again, drawn only when its text changed: Working Tree follows the work tree. */
export async function refresh() {
  if (asking) {
    again = true
    return asking
  }
  // A read that throws ends here too: the next change reads again.
  asking = (async () => {
    try {
      do {
        again = false
        const at = `${root} ${source}`
        const next = await oriel.git.diff(root, source).catch((error: Error) => error)
        if (at !== `${root} ${source}`) continue
        if (next instanceof Error) {
          // A diff drawn keeps its patch; a first read shows why it failed.
          if (patch === undefined) empty.textContent = next.message
        } else if (next !== patch) draw(next)
      } while (again)
    } finally {
      asking = undefined
    }
  })()
  return asking
}

/** A first read failed: a change in the work tree reads again. */
export const failed = () => patch === undefined

/** Side by Side wraps each column's lines: a line scrolled past its narrow column was cut off where a click lands.
 *  Unified wraps with Word Wrap. */
function overflow() {
  return split || wrap ? "wrap" : "scroll"
}

export function layout(next: { split?: boolean; wrap?: boolean }) {
  split = next.split ?? split
  wrap = next.wrap ?? wrap
  // Side by Side always wraps.
  control("diff.wrap", { enabled: !split })
  options.diffStyle = split ? "split" : "unified"
  options.overflow = overflow()
  viewer.setOptions({ ...options })
  keepChange()
}

export function toggleList() {
  list = !list
  nav.toggleAttribute("data-closed", !list)
  keep({ list })
  control("diff.file-list", { title: list ? "Hide File List" : "Show File List" })
  // Once the viewer has its new width: Side by Side wraps lines to it. With Reduce Motion there is no slide.
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) requestAnimationFrame(() => requestAnimationFrame(keepChange))
}
// After the slide: once, not for each of its properties.
nav.addEventListener("transitionend", (event) => event.target === nav && event.propertyName === "visibility" && keepChange())

export function step(by: 1 | -1) {
  if (!changes.length) return
  const next = by > 0 ? Math.floor(change) + 1 : Math.ceil(change) - 1
  change = Math.min(Math.max(next, 0), changes.length - 1)
  const place = changes[change]
  if (item(place.id).collapsed) collapse(place.id, false)
  viewer.scrollTo({ type: "line", ...place, align: "center" })
}
