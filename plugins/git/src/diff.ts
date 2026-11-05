// A Git card's diff, a page of its own (`ovvi.pages`): a source's patch in one scroll, each file a box with a sticky
// header and its lines in @pierre/diffs' VirtualizedFileDiff, and the file list beside it; a commit's subject, body and
// facts above its files. Row 2 has Git Home, the layout, the wrap, the list and previous / next change.
import type { Page } from "@ovvi/plugin-api"
import {
  type FileDiffMetadata,
  type FileDiffOptions,
  parsePatchFiles,
  preloadHighlighter,
  VirtualizedFileDiff,
  Virtualizer,
} from "@pierre/diffs"
import { element, failed as toast, fileIcon, home, type How, how, keep, kept, nameAndFolder, open, ovvi } from "./lib"

/** How near the view a file's box makes its view. */
const MARGIN = 1500
const letters = { change: "M", "rename-pure": "R", "rename-changed": "R", new: "A", deleted: "D" }

/** A file in the scroll: a box with its header, sticky in CSS inside the box, then its lines, drawn once it opens. */
type Box = { diff: FileDiffMetadata; node: HTMLElement; row: HTMLElement; lines: HTMLElement; folded: boolean
  /** Near the view once: its lines' view is made. */
  near?: boolean; view?: VirtualizedFileDiff<undefined> }

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
 *  tree. Its header controls, handlers and watch are the page's own (`place.ovvi`). */
export async function make(place: Page, root: string, source: string) {
  const api = place.ovvi
  const page = element("div")
  page.id = "diff"
  // The file list slides in and out as every plugin's sidebar (card.css).
  const nav = element("nav", "list ovvi-sidebar")
  const main = element("main", "diff")
  /** What scrolls: a commit's facts, then a box per file. */
  const content = element("div", "content")
  /** git's message when the first read failed. */
  const failure = element("p", "failure")
  /** No changes: the home's placeholder, in the middle; the file list gives way. */
  const clean = element("div", "placeholder")
  clean.hidden = true
  clean.innerHTML = `<span class="symbol" style="--symbol: var(--sf-checkmark-circle)"></span><h2>No changes</h2>`
  /** A commit's subject, body and facts, at the top of the scroll; empty for the working tree. */
  const about = element("header", "about")
  content.append(about)
  main.append(content)
  page.append(nav, main, failure, clean)
  place.element.append(page)

  /** The patch drawn, "" before the first; a failed read is undefined. */
  let patch: string | undefined
  let files: FileDiffMetadata[] = []
  /** Each file's box, by its name. */
  let boxes = new Map<string, Box>()
  // Each change block's first line, in order, for previous / next; the last one stepped to, or half a step before
  // the next one after a pick in the list.
  let changes: { id: string; lineNumber: number; side: "additions" | "deletions" }[] = []
  let change = -1
  /** The files marked Viewed, with their text then: a file that changes since drops the mark. */
  const viewed = new Map<string, string>()
  // Side by Side, the wrap and the file list as the user chose them in the card, else as the settings say.
  const own = kept()
  let split = (own.layout ?? ovvi.settings.get("diff-layout")) === "split"
  let wrap = own.wrap ?? ovvi.settings.get<boolean>("wrap")
  let list = own.list ?? ovvi.settings.get<boolean>("file-list")
  nav.toggleAttribute("data-closed", !list)

  // Each file's lines draw only near the view; its box keeps the whole file's height, so its header is sticky in CSS
  // alone and no script moves it.
  const virtualizer = new Virtualizer()
  virtualizer.setup(main, content)
  // A file's view is made once its box comes near the view: each costs about 1.5 ms (pierre puts its icons in each
  // box), 1.5 s for 1,000 files at once. Until then its box takes its estimated height.
  const owners = new WeakMap<Element, Box>()
  const nearby = new IntersectionObserver((entries) => steady(() => {
    for (const entry of entries) {
      const box = owners.get(entry.target)
      if (!entry.isIntersecting || !box || box.near) continue
      box.near = true
      show(box)
    }
  }), { root: main, rootMargin: `${MARGIN}px 0px` })
  place.keep(() => {
    nearby.disconnect()
    for (const box of boxes.values()) box.view?.cleanUp()
    virtualizer.cleanUp()
  })

  const options: FileDiffOptions<undefined, undefined> = {
    theme: { dark: "pierre-dark", light: "pierre-light" },
    themeType: ovvi.theme.dark ? "dark" : "light",
    diffStyle: split ? "split" : "unified",
    overflow: overflow(),
    lineDiffType: "word",
    // `N unmodified lines`, not expandable: that needs each file's whole text.
    hunkSeparators: "line-info-basic",
    // The box has its own header (`fileRow`).
    disableFileHeader: true,
    // The card's fill shows through.
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
      [data-separator-content] { background: none !important; color: var(--dim) }`,
  }

  /** A file's options: the page's, and ⌘-click on a line opens the file at the line in a new tab (⌥-click: to the
   *  side), or for a removed line at the one after it. */
  function fileOptions(box: Box): FileDiffOptions<undefined, undefined> {
    return {
      ...options,
      onLineClick: ({ event, lineNumber, annotationSide }) => {
        if ((event.metaKey || event.altKey) && box.diff.type !== "deleted") {
          openFile(box.diff.name, annotationSide === "additions" ? lineNumber : newLine(box.diff, lineNumber), how(event))
        }
      },
    }
  }

  /** The file's own row, as the card's rows: the disclosure, its icon, name and folder, its counts and letter, then
   *  Viewed and Open File. */
  function fileRow(box: Box) {
    const diff = box.diff, row = element("div", "file"), disclosure = element("button", "disclosure", "›")
    disclosure.ariaLabel = "Show or hide the file"
    disclosure.onclick = () => collapse(diff.name, !box.folded)
    const [base, dir] = nameAndFolder(diff.name)
    const name = element("span", "name", base)
    // A rename names its old path in the folder's place.
    const folder = element("span", "folder", diff.prevName && diff.prevName !== diff.name ? `from ${diff.prevName}` : dir)
    row.title = diff.name
    row.append(disclosure, fileIcon(diff.name), name, folder, ...counts(diff), letter(diff), actions(diff))
    return row
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

  /** A file's box as its fold has it: folded, or with no lines (binary, a mode change, a pure rename), its header
   *  alone; open, its lines, drawn the first time it opens near the view, and till then their estimated height (20 pt
   *  a row, 32 pt a hunk's gap, 8 pt above and below; the wrap is made up when it draws). */
  function show(box: Box) {
    const bare = box.folded || !box.diff.hunks.length
    box.node.classList.toggle("folded", bare)
    box.lines.hidden = bare
    box.row.querySelector(".disclosure")!.classList.toggle("shut", box.folded)
    if (bare || box.view) return
    if (!box.near) {
      box.lines.style.height = `${(split ? box.diff.splitLineCount : box.diff.unifiedLineCount) * 20 + box.diff.hunks.length * 32 + 16}px`
      return
    }
    box.lines.style.height = ""
    box.view = new VirtualizedFileDiff(fileOptions(box), virtualizer)
    box.view.render({ fileDiff: box.diff, fileContainer: box.lines })
  }

  /** Runs work that sizes boxes, and keeps the first box in view where it was: a box above it that changes height
   *  would move it. pierre's own anchor comes a frame later, after the move (WebKit's `overflow-anchor` is off: it would
   *  move it twice). At the very top, a file new above shows. */
  function steady(work: () => void) {
    if (!main.scrollTop) return work()
    const view = main.getBoundingClientRect().top
    const anchor = [...boxes.values()].find((box) => box.node.getBoundingClientRect().bottom > view)
    const offset = anchor ? top(anchor.node) - main.scrollTop : 0
    work()
    if (anchor?.node.isConnected) main.scrollTop = top(anchor.node) - offset
  }

  /** A commit's subject (also the card's title), its body, and its author, date, hash and parents; none for the working
   *  tree. */
  function describe(facts: Awaited<ReturnType<typeof ovvi.git.show>> | undefined) {
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
    copy.onclick = () => ovvi.clipboard.write(facts.hash).then(() => {
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
   * Draws a new patch. A file keeps its box, its place, its fold and its Viewed while its text is the same, and draws
   * nothing new. A Viewed file that changed opens again. A file new to the card with over 2,000 changed lines starts
   * folded.
   */
  function draw(next: string) {
    patch = next
    files = parsePatchFiles(patch).flatMap((parsed) => parsed.files)
    steady(() => put(files))
    changes = files.flatMap(blocks)
    shown()
    listFiles(files)
  }

  /** Each file in its box, in the patch's order. */
  function put(files: FileDiffMetadata[]) {
    const was = boxes, drawn: Box[] = []
    boxes = new Map()
    for (const file of files) {
      let box = was.get(file.name)
      was.delete(file.name)
      if (!box) {
        const { added, removed } = sums(file), node = element("section", "box")
        box = { diff: file, node, row: node, lines: document.createElement("diffs-container"), folded: added + removed > 2000 }
        owners.set(node, box)
        nearby.observe(node)
      } else if (text(box.diff) !== text(file) || box.diff.type !== file.type || box.diff.prevName !== file.prevName) {
        box.diff = file
        if (viewed.delete(file.name)) box.folded = false
        drawn.push(box)
      } else {
        boxes.set(file.name, box)
        continue
      }
      // A new header: its counts, its letter, its Viewed.
      box.row = fileRow(box)
      box.node.replaceChildren(box.row, box.lines)
      boxes.set(file.name, box)
    }
    for (const [name, box] of was) {
      viewed.delete(name)
      nearby.unobserve(box.node)
      box.view?.cleanUp()
    }
    // In the patch's order, moved only when it changed: a move lays the box out again.
    const order = [about, ...[...boxes.values()].map((box) => box.node)]
    if (order.some((node, index) => content.children[index] !== node) || content.children.length !== order.length) {
      content.replaceChildren(...order)
    }
    // Once in place: a file's lines draw by where its box sits. The boxes near the view draw now, not a frame later.
    for (const box of boxes.values()) show(box)
    const { top: from, bottom: to } = main.getBoundingClientRect()
    const near = [...boxes.values()].filter((box) => {
      const { top, bottom } = box.node.getBoundingClientRect()
      return !box.near && bottom > from - MARGIN && top < to + MARGIN
    })
    for (const box of near) {
      box.near = true
      show(box)
    }
    for (const box of drawn) box.view?.render({ fileDiff: box.diff, fileContainer: box.lines })
  }

  /** The file list: as the Git home's lists, a title with its count, then a row per file. */
  function listFiles(files: FileDiffMetadata[]) {
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
  }

  function openFile(name: string, line: number | undefined, how: How) {
    open(`${root}/${name}`, { how, at: line ? String(line) : undefined })
  }

  /** Where a node starts in the scroll. */
  function top(node: HTMLElement) {
    return node.getBoundingClientRect().top - main.getBoundingClientRect().top + main.scrollTop
  }

  /** The user's scrolls so far. */
  let wheels = 0
  main.addEventListener("wheel", () => wheels++, { passive: true })

  /** A change block in the middle of the view; its file opens first. Wrapped lines take their heights once drawn,
   *  a frame later: then once more. */
  function scrollToChange(block: (typeof changes)[number]) {
    const box = boxes.get(block.id)
    if (!box) return
    if (box.folded) collapse(block.id, false)
    box.near = true
    show(box)
    const aim = () => {
      const line = box.view?.getLinePosition(block.lineNumber, block.side)
      if (line) main.scrollTop = top(box.lines) + line.top + line.height / 2 - main.clientHeight / 2
    }
    aim()
    // Not after another step or the user's scroll meanwhile (pierre's own fixes of the scroll still aim again).
    const was = { change, wheels }
    if (options.overflow === "wrap") {
      requestAnimationFrame(() => requestAnimationFrame(() => change === was.change && wheels === was.wheels && aim()))
    }
  }

  /** Another layout or width gives the lines other heights: back to the change last stepped to, not wherever the old
   * offset now falls. */
  function keepChange() {
    if (changes[change]) scrollToChange(changes[change])
  }

  /** Folds or opens a file; a fold whose header stuck at the top keeps its box's top in view. */
  function collapse(id: string, folded: boolean) {
    const box = boxes.get(id)!
    box.folded = folded
    show(box)
    if (folded && top(box.node) < main.scrollTop) main.scrollTop = top(box.node)
  }

  function row(id: string) {
    return [...nav.children].find((node) => (node as HTMLElement).dataset.id === id)
  }

  function reveal(id: string) {
    const box = boxes.get(id)!
    if (box.folded) collapse(id, false)
    main.scrollTop = top(box.node)
    const order = (name: string) => files.findIndex((file) => file.name === name)
    const next = changes.findIndex((block) => order(block.id) >= order(id))
    change = (next < 0 ? changes.length : next) - 0.5
  }

  api.on("theme", (theme) => {
    options.themeType = theme.dark ? "dark" : "light"
    for (const box of boxes.values()) box.view?.setThemeType(options.themeType)
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

  const read = () => ovvi.git.diff(root, source).catch((error: Error) => error)

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
    steady(() => {
      for (const box of boxes.values()) {
        if (box.view) box.view.setOptions(fileOptions(box))
        else show(box)
      }
    })
    // Once the files have their new heights: pierre lays them out on the next frame.
    requestAnimationFrame(() => requestAnimationFrame(keepChange))
  }

  /** `chosen`: the user's, kept with the card; else the setting's. */
  function toggleList(chosen = true) {
    list = !list
    nav.toggleAttribute("data-closed", !list)
    if (chosen) keep({ list })
    api.controls.set("diff.file-list", { title: list ? "Hide File List" : "Show File List" })
    // Once the diff has its new width: Side by Side wraps lines to it. With Reduce Motion there is no slide.
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) requestAnimationFrame(() => requestAnimationFrame(keepChange))
  }
  // After the slide: once, not for each of its properties.
  nav.addEventListener("transitionend", (event) => event.target === nav && event.propertyName === "visibility" && keepChange())

  function step(by: 1 | -1) {
    if (!changes.length) return
    const next = by > 0 ? Math.floor(change) + 1 : Math.ceil(change) - 1
    change = Math.min(Math.max(next, 0), changes.length - 1)
    scrollToChange(changes[change])
  }

  api.on("control", ({ id, value }) => {
    if (id === "diff.home") ovvi.card.go(home(root))
    else if (id === "diff.layout") {
      keep({ layout: String(value) })
      layout({ split: value === "split" })
    } else if (id === "diff.wrap") {
      keep({ wrap: value === true })
      layout({ wrap: value === true })
    } else if (id === "diff.file-list") toggleList()
    else if (id === "diff.previous") step(-1)
    else if (id === "diff.next") step(1)
  })
  // While the page shows, the working tree asks for its patch again after each change under the root (and draws only
  // the files that changed), and a diff whose first read failed tries again; also once when it shows again.
  // A change while it draws calls once when it shows.
  api.files.watch(root, () => (source === "uncommitted" || patch === undefined) && void refresh())
  api.controls.set("diff.file-list", { title: list ? "Hide File List" : "Show File List" })
  api.controls.set("diff.wrap", { enabled: !split, value: wrap })
  api.controls.set("diff.layout", { value: split ? "split" : "unified" })
  // A new setting: what the user did not choose in the card follows it.
  api.on("settings", (changed) => {
    const own = kept()
    if ("diff-layout" in changed && own.layout === undefined) {
      api.controls.set("diff.layout", { value: String(changed["diff-layout"]) })
      layout({ split: changed["diff-layout"] === "split" })
    }
    if ("wrap" in changed && own.wrap === undefined) {
      api.controls.set("diff.wrap", { value: changed.wrap === true })
      layout({ wrap: changed.wrap === true })
    }
    if ("file-list" in changed && own.list === undefined && (changed["file-list"] === true) !== list) toggleList(false)
  })
  // Read first, then draw all of it in one go: the page before (the home, or the diff a Parent leaves) stays until
  // then, with no blank page while git answers. The themes first too: a file draws, and takes its height, only once
  // they are in (its words colored once its language is).
  const [next, facts] = await Promise.all([read(), source === "uncommitted"
    ? undefined
    : ovvi.git.show(root, source).catch(() => undefined),
  preloadHighlighter({ themes: [...new Set(Object.values(options.theme!))], langs: [] }).catch(console.error)])
  describe(facts)
  apply(next)
  if (place.at && files.some((file) => file.name === place.at)) reveal(place.at)
  // Back at this diff with a file (a change row of the home): a scroll to it.
  api.on("place", ({ at }) => at && files.some((file) => file.name === at) && reveal(at))
}
