// A Git card's diff: the pane's patch in @pierre/diffs' CodeView, one scroll with a sticky header per file, and the file
// list beside it. Row 2 (DiffToolbar.swift) sends the layout, the list and previous / next change.
import {
  CodeView,
  type CodeViewDiffItem,
  type CodeViewOptions,
  type FileDiffMetadata,
  parsePatchFiles,
} from "@pierre/diffs"
import { ask, at, type How, how, type PatchReply, receive, report } from "./lib/bridge"
import "./diff.css"


const letters = { change: "M", "rename-pure": "R", "rename-changed": "R", new: "A", deleted: "D" }
const nav = element("nav", "list")
const main = element("main", "diff")
const empty = element("p", "empty")
document.body.append(nav, main, empty)

// A first ask that fails (a folder not yet a repo, a machine away) waits for a change in the work tree.
let reply: PatchReply | undefined
while (!reply) {
  reply = await ask({ op: "patch" }).catch((error: Error) => {
    empty.textContent = error.message
    report({ op: "ready" })
    return undefined
  })
  if (!reply) await new Promise<void>((resolve) => receive(() => resolve()))
}
const { root, split, list, symbols } = reply
// The app's SF Symbols, as masks (git.ts has the same); in a style sheet: the app sets the root's own style.
const sheet = element("style")
sheet.textContent = `:root { ${Object.entries(symbols).map(([name, url]) => `--sf-${name.replaceAll(".", "-")}: url(${url});`).join(" ")} }`
document.head.append(sheet)
let patch = ""
let files: FileDiffMetadata[] = []
// Each change block's first line, in order, for previous / next; the last one stepped to, or half a step before
// the next one after a pick in the list.
let changes: { id: string; lineNumber: number; side: "additions" | "deletions" }[] = []
let change = -1
/** The files marked Viewed, with their text then: a file that changes since drops the mark. */
const viewed = new Map<string, string>()
nav.hidden = !list

const options: CodeViewOptions<undefined, undefined> = {
  theme: { dark: "pierre-dark", light: "pierre-light" },
  themeType: scheme(),
  diffStyle: split ? "split" : "unified",
  // Side by Side wraps each column's lines: a line scrolled past its narrow column was cut off where a click lands.
  overflow: split ? "wrap" : "scroll",
  lineDiffType: "word",
  // `N unmodified lines`, not expandable: that needs each file's whole text.
  hunkSeparators: "line-info-basic",
  stickyHeaders: true,
  // Clicks right after Next Change or a pick in the list (CodeView drops them while it scrolls).
  pointerEventsOnScroll: true,
  layout: { paddingTop: 0, paddingBottom: 24, gap: 0 },
  // The card's fill shows through; the sticky header is opaque in the card's color, with a line under it.
  unsafeCSS: `
    [data-diffs-header] :is([data-additions-count], [data-deletions-count]) { display: none }
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
    [data-diffs-header] {
      background: var(--card) !important;
      box-shadow: inset 0 -0.5px var(--divider);
      cursor: default;
    }`,
  renderHeaderPrefix: (diff: FileDiffMetadata) => {
    const button = header(diff, "prefix", () => {
      const button = element("button", "disclosure", "›")
      button.ariaLabel = "Show or hide the file"
      button.onclick = () => collapse(diff.name, !item(diff.name).collapsed)
      return button
    })
    button.classList.toggle("shut", Boolean(item(diff.name)?.collapsed))
    return button
  },
  renderHeaderMetadata: (diff: FileDiffMetadata) => header(diff, "metadata", () => {
    const box = element("span", "actions")
    box.append(...counts(diff))
    const label = element("label", "mark")
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
  }),
  // ⌘-click: the file at the line in a new tab (⌥-click: to the side), or for a removed line at the one after it.
  onLineClick: ({ event, lineNumber, annotationSide }, context) => {
    const file = files.find((file) => file.name === context.item.id)
    if ((event.metaKey || event.altKey) && file && file.type !== "deleted") {
      openFile(file.name, annotationSide === "additions" ? lineNumber : newLine(file, lineNumber), how(event))
    }
  },
}
/**
 * A file's header controls, made once per text: pierre asks for them at every render of the file (a scroll, the
 * highlighter's answer), and a click whose press and release land on two different nodes does nothing.
 */
const headers = new Map<string, { text: string; node: HTMLElement }>()
function header(diff: FileDiffMetadata, slot: string, make: () => HTMLElement) {
  const key = `${slot} ${diff.name}`, body = text(diff), made = headers.get(key)
  if (made?.text === body) return made.node
  const node = make()
  headers.set(key, { text: body, node })
  return node
}

const viewer = new CodeView(options)
viewer.setup(main)
show(reply.patch)
report({ op: "ready" })
if (at && files.some((file) => file.name === at)) reveal(at)

/**
 * Draws a new patch. A file keeps its place, its fold and its Viewed while its text is the same; a Viewed file that
 * changed opens again. A file new to the card with over 2,000 changed lines starts folded.
 */
function show(next: string) {
  patch = next
  files = parsePatchFiles(patch).flatMap((parsed) => parsed.files)
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
    return { id: fileDiff.name, type: "diff", fileDiff, collapsed: viewed.has(fileDiff.name) || folded }
  }))
  changes = files.flatMap(blocks)
  change = -1
  empty.textContent = files.length ? "" : "No changes"
  // As the Git home's lists: a title, its count after it.
  const title = element("header", "title")
  title.append(element("h2", "", "Files"), element("span", "count", files.length ? String(files.length) : ""))
  nav.replaceChildren(title)
  for (const file of files) {
    const button = element("button", viewed.has(file.name) ? "row viewed" : "row")
    button.dataset.id = file.name
    const slash = file.name.lastIndexOf("/")
    const symbol = element("span", "symbol")
    symbol.style.setProperty("--symbol", "var(--sf-doc)")
    symbol.ariaHidden = "true"
    button.append(
      symbol,
      element("span", "name", file.name.slice(slash + 1)),
      element("span", "folder", file.name.slice(0, Math.max(slash, 0))),
      ...counts(file),
      element("span", `letter ${letters[file.type]}`, letters[file.type]),
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

function element<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, content = "") {
  const node = document.createElement(tag)
  node.className = className
  node.textContent = content
  return node
}

function openFile(name: string, line: number | undefined, how: How) {
  report({ op: "open", arg: `${root}/${name}`, at: line ? String(line) : undefined, how })
}

/** Another layout or width gives the lines other heights: back to the change last stepped to, not wherever the old
 * offset now falls. */
function keepChange() {
  if (changes[change]) viewer.scrollTo({ type: "line", ...changes[change], align: "center" })
}

function scheme() {
  return document.documentElement.style.colorScheme === "light" ? "light" : "dark"
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

// The host sets `color-scheme` on the root with the app's look.
new MutationObserver(() => {
  options.themeType = scheme()
  viewer.setOptions({ ...options })
}).observe(document.documentElement, { attributeFilter: ["style"] })

// One patch at a time; a change during one asks again after it.
let asking = false
let again = false
async function refresh() {
  if (asking) {
    again = true
    return
  }
  asking = true
  do {
    again = false
    const reply: PatchReply | undefined = await ask({ op: "patch" }).catch(() => undefined)
    if (reply && reply.patch !== patch) show(reply.patch)
  } while (again)
  asking = false
}

receive((message) => {
  switch (message.op) {
    // Another change of the same Uncommitted diff picked on the home.
    case "reveal":
      if (files.some((file) => file.name === message.at)) reveal(message.at)
      break
    case "changed":
      refresh()
      break
    case "layout":
      options.diffStyle = message.split ? "split" : "unified"
      options.overflow = message.split ? "wrap" : "scroll"
      viewer.setOptions({ ...options })
      keepChange()
      break
    case "list":
      nav.hidden = !message.open
      // Once the viewer has its new width: Side by Side wraps lines to it.
      requestAnimationFrame(() => requestAnimationFrame(keepChange))
      break
    case "step": {
      if (!changes.length) return
      const step = message.by > 0 ? Math.floor(change) + 1 : Math.ceil(change) - 1
      change = Math.min(Math.max(step, 0), changes.length - 1)
      const place = changes[change]
      if (item(place.id).collapsed) collapse(place.id, false)
      viewer.scrollTo({ type: "line", ...place, align: "center" })
    }
  }
})
