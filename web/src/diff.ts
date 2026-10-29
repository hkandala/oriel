// The Diff card: the pane's patch in @pierre/diffs' CodeView, one scroll with a sticky header per file, and the file
// list beside it. Row 2 (DiffToolbar.swift) sends the layout, the list and previous / next change.
import {
  CodeView,
  type CodeViewDiffItem,
  type CodeViewOptions,
  type FileDiffMetadata,
  parsePatchFiles,
} from "@pierre/diffs"
import { ask, at, type PatchReply, receive, report } from "./lib/bridge"

const style = document.createElement("style")
style.textContent = `
  body { display: flex; --diffs-font-family: ui-monospace, monospace; --diffs-font-size: var(--font-size);
    --diffs-header-font-family: system-ui; user-select: none; -webkit-user-select: none }
  .list { flex: none; width: clamp(160px, 28%, 260px); overflow-y: auto; padding: 4px 6px 12px 0;
    border-right: 0.5px solid var(--divider); box-sizing: border-box }
  .count { color: var(--dim); font-size: 11px; font-weight: 600; text-transform: uppercase; padding: 6px 8px }
  .row { all: unset; box-sizing: border-box; display: flex; gap: 4px; align-items: baseline; width: 100%;
    padding: 3px 8px; border-radius: 6px; white-space: nowrap }
  .row:hover { background: color-mix(in srgb, var(--text) 8%, transparent) }
  .row.viewed .name { color: var(--dim) }
  .name { flex: none; max-width: 70%; overflow: hidden; text-overflow: ellipsis }
  .folder { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis;
    color: var(--dim); font-size: 11px }
  .added, .removed, .letter { flex: none; font: 11px ui-monospace, monospace }
  .actions .added, .actions .removed { font-size: inherit }
  .added { color: var(--finished) } .removed { color: var(--error) }
  .letter { width: 1.5ch; text-align: right; font-weight: 600; color: var(--working) }
  .letter.A { color: var(--finished) } .letter.D { color: var(--error) } .letter.R { color: var(--needs-you) }
  .diff { flex: 1; min-width: 0; overflow: auto }
  .empty { position: fixed; inset: 0; margin: auto; height: fit-content; text-align: center; color: var(--dim) }
  .disclosure, .open { all: unset; color: var(--dim); border-radius: 5px; padding: 1px 6px }
  .disclosure:hover, .open:hover { color: var(--text); background: color-mix(in srgb, var(--text) 10%, transparent) }
  .actions { display: flex; align-items: center; gap: 10px; margin-left: 10px; font: 12px system-ui;
    color: var(--dim) }
  .mark { display: flex; align-items: center; gap: 4px }
  .disclosure { display: inline-block; transform: rotate(90deg); transition: transform 0.15s }
  .disclosure.shut { transform: none }
`
document.head.append(style)

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
    return undefined
  })
  if (!reply) await new Promise<void>((resolve) => receive(() => resolve()))
}
const { root, split, list } = reply
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
  lineDiffType: "word",
  // `N unmodified lines`, not expandable: that needs each file's whole text.
  hunkSeparators: "line-info-basic",
  stickyHeaders: true,
  layout: { paddingTop: 0, paddingBottom: 24, gap: 0 },
  // The card's fill shows through; the sticky header blurs what scrolls under it.
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
      background: color-mix(in srgb, var(--text) 6%, transparent) !important;
      backdrop-filter: blur(20px);
      cursor: default;
    }`,
  renderHeaderPrefix: (diff: FileDiffMetadata) => {
    const button = element("button", item(diff.name)?.collapsed ? "disclosure shut" : "disclosure", "›")
    button.ariaLabel = "Show or hide the file"
    button.onclick = () => collapse(diff.name, !item(diff.name).collapsed)
    return button
  },
  renderHeaderMetadata: (diff: FileDiffMetadata) => {
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
      open.onclick = () => openFile(diff.name)
      box.append(open)
    }
    return box
  },
  // ⌘-click: the file, at the line when it is in the new file.
  // ⌘-click: the file at the line, or for a removed line at the one after it.
  onLineClick: ({ event, lineNumber, annotationSide }, context) => {
    const file = files.find((file) => file.name === context.item.id)
    if (event.metaKey && file && file.type !== "deleted") {
      openFile(file.name, annotationSide === "additions" ? lineNumber : newLine(file, lineNumber))
    }
  },
}
const viewer = new CodeView(options)
viewer.setup(main)
show(reply.patch)
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
  nav.replaceChildren(element("div", "count", `${files.length} ${files.length === 1 ? "file" : "files"}`))
  for (const file of files) {
    const button = element("button", viewed.has(file.name) ? "row viewed" : "row")
    button.dataset.id = file.name
    const slash = file.name.lastIndexOf("/")
    button.append(
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

function openFile(name: string, line?: number) {
  report({ op: "open", arg: `${root}/${name}`, at: line ? String(line) : undefined })
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
    case "changed":
      refresh()
      break
    case "layout":
      options.diffStyle = message.split ? "split" : "unified"
      viewer.setOptions({ ...options })
      break
    case "list":
      nav.hidden = !message.open
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
