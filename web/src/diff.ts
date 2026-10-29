// The Diff card: the pane's patch in @pierre/diffs' CodeView, one scroll with a sticky header per file, and the file
// list beside it. Row 2 (DiffToolbar.swift) sends the layout, the list and previous / next change.
import {
  CodeView,
  type CodeViewDiffItem,
  type CodeViewOptions,
  type FileDiffMetadata,
  parsePatchFiles,
} from "@pierre/diffs"
import { ask, at, receive, report } from "./lib/bridge"

const style = document.createElement("style")
style.textContent = `
  body { display: flex; --diffs-font-family: ui-monospace, monospace; --diffs-font-size: var(--font-size);
    --diffs-header-font-family: system-ui; user-select: none; -webkit-user-select: none }
  .list { flex: none; width: clamp(160px, 28%, 260px); overflow-y: auto; padding: 4px 6px 12px 0;
    border-right: 0.5px solid var(--divider); box-sizing: border-box }
  .list[hidden] { display: none }
  .count { color: var(--dim); font-size: 11px; font-weight: 600; text-transform: uppercase; padding: 6px 8px }
  .row { all: unset; box-sizing: border-box; display: flex; gap: 4px; align-items: baseline; width: 100%;
    padding: 3px 8px; border-radius: 6px; white-space: nowrap }
  .row:hover { background: color-mix(in srgb, var(--text) 8%, transparent) }
  .row.viewed .name { color: var(--dim) }
  .name { flex: none; max-width: 70%; overflow: hidden; text-overflow: ellipsis }
  .folder { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis;
    color: var(--dim); font-size: 11px }
  .added, .removed, .letter { flex: none; font: 11px ui-monospace, monospace }
  .added { color: var(--finished) } .removed { color: var(--error) }
  .letter { width: 1.5ch; text-align: right; font-weight: 600; color: var(--working) }
  .letter.A { color: var(--finished) } .letter.D { color: var(--error) } .letter.R { color: var(--needs-you) }
  .diff { flex: 1; min-width: 0; overflow: auto }
  .empty { position: fixed; inset: 0; margin: auto; height: fit-content; text-align: center; color: var(--dim) }
  .empty:empty { display: none }
  .disclosure, .open { all: unset; color: var(--dim); border-radius: 5px; padding: 1px 6px }
  .disclosure:hover, .open:hover { color: var(--text); background: color-mix(in srgb, var(--text) 10%, transparent) }
  .actions { display: flex; align-items: center; gap: 10px; margin-left: 10px; font: 12px system-ui;
    color: var(--dim) }
  .viewed { display: flex; align-items: center; gap: 4px }
  .disclosure { display: inline-block; transform: rotate(90deg); transition: transform 0.15s }
  .disclosure.shut { transform: none }
`
document.head.append(style)

const letters = { change: "M", "rename-pure": "R", "rename-changed": "R", new: "A", deleted: "D" }
const nav = element("nav", "list")
const main = element("main", "diff")
const empty = element("p", "empty")
document.body.append(nav, main, empty)

const { root, split, list, ...first } = await ask({ op: "patch" }).catch((error: Error) => {
  empty.textContent = error.message
  throw error
})
let patch = ""
let files: FileDiffMetadata[] = []
// Each change block's first line, in order, for previous / next; the last one stepped to.
let changes: { id: string; lineNumber: number; side: "additions" | "deletions" }[] = []
let change = -1
/** The files marked Viewed, with their text then: a file that changes since drops the mark. */
const viewed = new Map<string, string>()
nav.hidden = !list
main.ariaLabel = split ? "Side by Side" : "Unified"

const options: CodeViewOptions<undefined, undefined> = {
  theme: { dark: "pierre-dark", light: "pierre-light" },
  themeType: scheme(),
  diffStyle: split ? "split" : "unified",
  lineDiffType: "word",
  stickyHeaders: true,
  layout: { paddingTop: 0, paddingBottom: 24, gap: 0 },
  // The card's fill shows through; the sticky header blurs what scrolls under it.
  unsafeCSS: `
    :host { --diffs-light-bg: transparent !important; --diffs-dark-bg: transparent !important }
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
    const label = element("label", "viewed")
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
    const open = element("button", "open", "Open File")
    open.ariaLabel = `Open ${diff.name}`
    open.onclick = () => openFile(diff.name)
    box.append(label, open)
    return box
  },
  // ⌘-click: the file, at the line when it is in the new file.
  onLineClick: ({ event, lineNumber, annotationSide }, context) => {
    if (event.metaKey) openFile(context.item.id, annotationSide === "additions" ? lineNumber : undefined)
  },
}
const viewer = new CodeView(options)
viewer.setup(main)
show(first.patch)
if (at && files.some((file) => file.name === at)) reveal(at)

/** Draws a new patch; the same files keep their place and their Viewed while their text is the same. */
function show(next: string) {
  patch = next
  files = parsePatchFiles(patch).flatMap((parsed) => parsed.files)
  for (const [name, was] of viewed) {
    const file = files.find((file) => file.name === name)
    if (!file || text(file) !== was) viewed.delete(name)
  }
  viewer.setItems(files.map((fileDiff) => ({
    id: fileDiff.name, type: "diff", fileDiff, collapsed: viewed.has(fileDiff.name),
  })))
  changes = files.flatMap(blocks)
  change = -1
  empty.textContent = files.length ? "" : "No changes"
  nav.replaceChildren(element("div", "count", `${files.length} ${files.length === 1 ? "file" : "files"}`))
  for (const file of files) {
    let added = 0
    let removed = 0
    for (const hunk of file.hunks) {
      added += hunk.additionLines
      removed += hunk.deletionLines
    }
    const button = element("button", viewed.has(file.name) ? "row viewed" : "row")
    button.dataset.id = file.name
    const slash = file.name.lastIndexOf("/")
    button.append(
      element("span", "name", file.name.slice(slash + 1)),
      element("span", "folder", file.name.slice(0, Math.max(slash, 0))),
      element("span", "added", added ? `+${added}` : ""),
      element("span", "removed", removed ? `−${removed}` : ""),
      element("span", `letter ${letters[file.type]}`, letters[file.type]),
    )
    button.title = file.name
    button.ariaLabel = file.name
    button.onclick = () => reveal(file.name)
    nav.append(button)
  }
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
  change = changes.findIndex((place) => place.id === id) - 1
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
    const reply = await ask({ op: "patch" }).catch(() => undefined)
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
      main.ariaLabel = message.split ? "Side by Side" : "Unified"
      viewer.setOptions({ ...options })
      break
    case "list":
      nav.hidden = !message.open
      break
    case "step": {
      if (!changes.length) return
      change = Math.min(Math.max(change + message.by, 0), changes.length - 1)
      const place = changes[change]
      if (item(place.id).collapsed) collapse(place.id, false)
      viewer.scrollTo({ type: "line", ...place, align: "center" })
    }
  }
})
