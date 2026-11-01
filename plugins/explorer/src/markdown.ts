// The Markdown place: one CodeMirror view of the file in both modes, drawn as rendered Markdown (a live preview).
// Read is the view not editable with every line drawn; Edit puts back the marks of the caret's lines. So a switch
// moves nothing on screen but the caret's line. Tables and HTML blocks draw through markdown-it unless the caret is in
// them. The outline lists the headings; row 2 picks the mode and the outline, and the page sets them when it changes
// them itself.
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { yamlFrontmatter } from "@codemirror/lang-yaml"
import { ensureSyntaxTree, HighlightStyle, syntaxHighlighting, syntaxTree } from "@codemirror/language"
import { closeSearchPanel } from "@codemirror/search"
import { Compartment, EditorState, Prec, type Range, StateField } from "@codemirror/state"
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate, WidgetType } from "@codemirror/view"
import type { SyntaxNode } from "@lezer/common"
import { tags } from "@lezer/highlight"
import MarkdownIt from "markdown-it"
import { type Editor, editor } from "./editor"
import { how, open, type Place, type Reveal } from "./place"

const md = new MarkdownIt({ html: true, linkify: true })
// Images are not loaded: their alt text links to them, as in a Markdown image's own line.
md.renderer.rules.image = (tokens, i) => {
  const { escapeHtml } = md.utils
  const src = String(tokens[i].attrGet("src") ?? "")
  return `<a href="${escapeHtml(src)}">${escapeHtml(tokens[i].content || src)}</a>`
}

/** GitHub's anchor of a heading's text, for `#` links. */
const slug = (text: string) => text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s/g, "-")

/** The mode is the view's `editable`: Edit when it is, and the caret's lines show their marks. */
const editing = (state: EditorState) => state.facet(EditorView.editable)
const switched = (start: EditorState, now: EditorState) => editing(start) !== editing(now)
/** Read: no text box for VoiceOver, an article; read only, so a drag, a drop or a cut changes nothing. */
const mode = (edit: boolean) => [
  EditorView.editable.of(edit),
  EditorState.readOnly.of(!edit),
  edit ? [] : Prec.highest(EditorView.contentAttributes.of({ role: "article", "aria-readonly": "true" })),
]
const modeClass = EditorView.editorAttributes.compute([EditorView.editable], (state) => ({
  class: editing(state) ? "" : "cm-reading",
}))
/** The nodes that hold blocks: the walks over the document's blocks go into these only. */
const containers = ["Document", "Blockquote", "BulletList", "OrderedList", "ListItem"]

/** The lines the caret or the selection touches in Edit, as ranges; none in Read. */
function active(state: EditorState) {
  if (!editing(state)) return []
  return state.selection.ranges.map((range) => ({
    from: state.doc.lineAt(range.from).from,
    to: state.doc.lineAt(range.to).to,
  }))
}
const touches = (lines: { from: number; to: number }[], from: number, to: number) =>
  lines.some((line) => line.from <= to && line.to >= from)

/** A table or an HTML block as markdown-it draws it; a click puts the caret in its source (in Edit). */
class Block extends WidgetType {
  constructor(readonly source: string) {
    super()
  }
  eq(other: Block) {
    return other.source === this.source
  }
  toDOM(view: EditorView) {
    const block = Object.assign(document.createElement("div"), { className: "cm-md-block" })
    block.innerHTML = md.render(this.source)
    block.onmousedown = (event) => {
      if (!editing(view.state) || (event.target as Element).closest("a")) return
      event.preventDefault()
      view.dispatch({ selection: { anchor: view.posAtDOM(block) } })
      view.focus()
    }
    return block
  }
  ignoreEvent() {
    return false
  }
}

/** Tables, HTML blocks and comments, drawn whole unless the caret is in them (a comment draws nothing): block widgets
 *  live in the state, not a plugin.
 *  ponytail: walks the document's top blocks at each change of the caret; per viewport if long files lag. */
function blocks(state: EditorState): DecorationSet {
  const ranges: Range<Decoration>[] = []
  const lines = active(state)
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name === "Table" || node.name === "HTMLBlock" || node.name === "CommentBlock") {
        const from = state.doc.lineAt(node.from).from, to = state.doc.lineAt(node.to).to
        if (!touches(lines, from, to)) {
          ranges.push(Decoration.replace({ widget: new Block(state.sliceDoc(from, to)), block: true }).range(from, to))
        }
        return false
      }
      return containers.includes(node.name)
    },
  })
  return Decoration.set(ranges, true)
}
const blockField = StateField.define<DecorationSet>({
  create: blocks,
  update: (set, tr) =>
    tr.docChanged || tr.selection || switched(tr.startState, tr.state)
      || syntaxTree(tr.startState) !== syntaxTree(tr.state) ? blocks(tr.state) : set,
  provide: (field) => EditorView.decorations.from(field),
})

/** A list item's bullet or number, at its depth: the line hangs after it, as Read's list. */
class Bullet extends WidgetType {
  constructor(readonly text: string, readonly width: number) {
    super()
  }
  eq(other: Bullet) {
    return other.text === this.text && other.width === this.width
  }
  toDOM() {
    const bullet = Object.assign(document.createElement("span"), { className: "cm-md-bullet", textContent: this.text })
    bullet.style.width = `${this.width}em`
    return bullet
  }
}

/** A task's box, as Read draws it. */
class Box extends WidgetType {
  constructor(readonly checked: boolean) {
    super()
  }
  eq(other: Box) {
    return other.checked === this.checked
  }
  toDOM() {
    return Object.assign(document.createElement("input"), { type: "checkbox", disabled: true, checked: this.checked })
  }
}

/** A thematic break's line. */
class Rule extends WidgetType {
  eq() {
    return true
  }
  toDOM() {
    return Object.assign(document.createElement("span"), { className: "cm-md-hr" })
  }
}

const hide = Decoration.replace({})
const line = (className: string) => Decoration.line({ class: className })
const frontmatter = Decoration.mark({ class: "cm-frontmatter" })
const quote = Decoration.line({ class: "cm-md-quote" })
const code = Decoration.mark({ class: "cm-md-code" })
// The marks of an element, hidden off the caret's lines: a heading's `#`, emphasis, a link's brackets and address,
// code ticks. A setext heading's underline stays: hidden, it would leave an empty line.
const marks = new Set(["HeaderMark", "EmphasisMark", "StrikethroughMark", "LinkMark", "URL", "LinkTitle", "CodeMark"])
const kept = new Set(["FencedCode", "Autolink", "LinkReference", "SetextHeading1", "SetextHeading2"])
/** One em per depth for a bullet, as Read's lists indent. */
const INDENT = 1.6

/** The link a Link, Image or Autolink node points to. */
function href(node: SyntaxNode, state: EditorState) {
  const url = node.getChild("URL")
  return url ? state.sliceDoc(url.from, url.to).replace(/^<|>$/g, "") : ""
}

/** The rendered look of the visible lines: marks hidden off the caret's lines, line styles for headings, lists,
 *  quotes and code, links as links. */
function preview(view: EditorView): DecorationSet {
  const { state } = view
  const ranges: Range<Decoration>[] = []
  const lines = active(state)
  /** The line of `pos` is a caret's. */
  const raw = (pos: number) => touches(lines, pos, pos)
  /** After one space at `pos`: a mark takes its space along. */
  const past = (pos: number) => (state.sliceDoc(pos, pos + 1) === " " ? pos + 1 : pos)
  /** The visible range walked now. */
  let from = 0, to = 0
  /** Each line of a node that is in view. */
  const shown = (node: { from: number; to: number }) => {
    const first = state.doc.lineAt(Math.max(node.from, from)).number
    const last = state.doc.lineAt(Math.min(node.to, to)).number
    return Array.from({ length: last - first + 1 }, (_, i) => state.doc.line(first + i))
  }
  for (const range of view.visibleRanges) {
    ;({ from, to } = range)
    syntaxTree(state).iterate({
      from,
      to,
      enter(node) {
        const name = node.name, parent = node.node.parent
        if (name === "Frontmatter") ranges.push(frontmatter.range(node.from, node.to))
        const heading = /^(?:ATX|Setext)Heading(\d)$/.exec(name)?.[1]
        if (heading) {
          const attributes = { role: "heading", "aria-level": heading }
          ranges.push(Decoration.line({ class: `cm-md-h${heading}`, attributes }).range(state.doc.lineAt(node.from).from))
        }
        if (name === "InlineCode") ranges.push(code.range(node.from, node.to))
        if (name === "Link" || name === "Image" || name === "Autolink" || (name === "URL" && !["Link", "Image", "Autolink"].includes(parent?.name ?? ""))) {
          const url = name === "URL" ? state.sliceDoc(node.from, node.to) : href(node.node, state)
          const marks = node.node.getChildren("LinkMark")
          const textFrom = name === "URL" || name === "Autolink" ? node.from : (marks[0]?.to ?? node.from)
          const textTo = name === "URL" || name === "Autolink" ? node.to : (marks[1]?.from ?? node.to)
          if (url && textTo > textFrom) {
            ranges.push(Decoration.mark({ tagName: "a", attributes: { href: url } }).range(textFrom, textTo))
          }
        }
        if (name === "Blockquote") for (const each of shown(node)) ranges.push(quote.range(each.from))
        if (name === "FencedCode" || name === "CodeBlock") {
          const first = state.doc.lineAt(node.from).number, last = state.doc.lineAt(node.to).number
          // The fences' lines: a block not closed yet has only its opening one.
          const fences = new Set(node.node.getChildren("CodeMark").map((mark) => state.doc.lineAt(mark.from).number))
          for (const each of shown(node)) {
            const n = each.number, fence = fences.has(n) && !raw(each.from)
            const edge = `${n === first ? " cm-md-pre-first" : ""}${n === last ? " cm-md-pre-last" : ""}`
            ranges.push(line(`cm-md-pre${edge}${fence ? " cm-md-fence" : ""}`).range(each.from))
            if (fence && each.to > each.from) ranges.push(hide.range(each.from, each.to))
          }
          return false
        }
        // An escape's backslash.
        if (name === "Escape" && !raw(node.from)) ranges.push(hide.range(node.from, node.from + 1))
        if (name === "HorizontalRule" && !raw(node.from)) {
          ranges.push(Decoration.replace({ widget: new Rule() }).range(node.from, node.to))
        }
        if (name === "ListMark" && parent?.name === "ListItem") {
          const each = state.doc.lineAt(node.from)
          let depth = 0
          for (let at = node.node.parent; at; at = at.parent) depth += Number(/^(Bullet|Ordered)List$/.test(at.name))
          const width = depth * INDENT
          // On the caret's line the mark shows where the bullet was, its text a little to the right.
          const style = raw(node.from)
            ? `padding-left: calc(${width - 1}em + 6px)`
            : `padding-left: calc(${width + 0.4}em + 6px); text-indent: -${width + 0.4}em`
          ranges.push(Decoration.line({ class: "cm-md-li", attributes: { style } }).range(each.from))
          if (!raw(node.from)) {
            const task = parent.getChild("Task")
            const text = task ? "" : parent.parent?.name === "OrderedList" ? state.sliceDoc(node.from, node.to) : "•"
            ranges.push(Decoration.replace({ widget: new Bullet(text, width) }).range(each.from, past(node.to)))
          }
        }
        if (name === "QuoteMark" && !raw(node.from)) ranges.push(hide.range(node.from, past(node.to)))
        if (name === "TaskMarker" && !raw(node.from)) {
          const checked = state.sliceDoc(node.from + 1, node.to - 1) !== " "
          ranges.push(Decoration.replace({ widget: new Box(checked) }).range(node.from, past(node.to)))
        }
        if (!marks.has(name) || !parent || kept.has(parent.name)) return
        // A bare address (GFM) is the text itself.
        if (name === "URL" && parent.name !== "Link" && parent.name !== "Image") return
        if (touches(lines, parent.from, parent.to)) return
        ranges.push(hide.range(node.from, name === "HeaderMark" ? past(node.to) : node.to))
      },
    })
  }
  return Decoration.set(ranges, true)
}

const livePreview = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet
    constructor(view: EditorView) {
      this.decorations = preview(view)
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet || update.viewportChanged
        || switched(update.startState, update.state)
        || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        this.decorations = preview(update.view)
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
)

const look = HighlightStyle.define([
  { tag: [tags.heading, tags.strong], fontWeight: "600" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.link, color: "var(--accent)" },
  { tag: [tags.url, tags.processingInstruction, tags.quote], color: "var(--dim)" },
  { tag: tags.monospace, fontFamily: "ui-monospace, monospace", fontSize: "0.9em" },
])

/** The headings in the editor's syntax tree, at the top level, in lists and in quotes: their line and text. */
function headings(state: EditorState, tree = syntaxTree(state)) {
  const found: { from: number; level: number; text: string }[] = []
  tree.iterate({
    enter(node) {
      const level = /^(?:ATX|Setext)Heading(\d)$/.exec(node.name)?.[1]
      if (!level) return containers.includes(node.name)
      const line = state.doc.lineAt(node.from)
      // The text between an ATX heading's marks, or a setext heading's first line.
      const [first, last] = node.node.getChildren("HeaderMark")
      const text = node.name.startsWith("ATX")
        ? state.sliceDoc(first?.to ?? node.from, last?.from ?? node.to)
        : state.sliceDoc(node.from, line.to)
      found.push({ from: line.from, level: Number(level), text: text.trim() || line.text })
      return false
    },
  })
  return found
}

/** Read's selection as source text: the page's selection mapped onto the document (an end outside the editor is the
 *  document's end), else the editor's own; undefined when the selection is not in the editor. */
function copied(view: EditorView) {
  const selection = getSelection(), content = view.contentDOM
  const range = selection && !selection.isCollapsed ? selection.getRangeAt(0) : undefined
  if (range?.intersectsNode(content)) {
    const end = (node: Node, offset: number, outside: number) =>
      content.contains(node) ? view.posAtDOM(node, offset) : outside
    return view.state.sliceDoc(end(range.startContainer, range.startOffset, 0),
      end(range.endContainer, range.endOffset, view.state.doc.length))
  }
  const main = view.state.selection.main
  return main.empty ? undefined : view.state.sliceDoc(main.from, main.to)
}

export async function show(place: Place): Promise<Reveal> {
  const { oriel, arg, keep, root } = place
  const outline = Object.assign(document.createElement("nav"), { className: "oriel-sidebar" })
  const pane = document.createElement("main")
  // Shown once the file is: not beside the info view. Closed until the outline is on, then it slides.
  outline.hidden = true
  outline.toggleAttribute("data-closed", true)
  root.append(outline, pane)
  let edit = false
  let outlined = false
  const editable = new Compartment()

  /** Shows Read or Edit and the outline or not, and sets row 2 and Edit Mode to match. */
  function present(view: EditorView, nowEdit: boolean, nowOutlined: boolean) {
    if (nowEdit !== edit) {
      // Read keeps no selection drawn, nor a search panel (its Replace would write).
      if (!nowEdit) closeSearchPanel(view)
      const selection = nowEdit ? undefined : { anchor: view.state.selection.main.head }
      view.dispatch({ selection, effects: editable.reconfigure(mode(nowEdit)) })
    }
    edit = nowEdit
    outlined = nowOutlined
    outline.hidden = false
    outline.toggleAttribute("data-closed", !outlined)
    // The whole document's headings: the background parse stops past the viewport.
    if (outlined) list(view, ensureSyntaxTree(view.state, view.state.doc.length, 200) ?? undefined)
    focus(view)
    oriel.controls.set("mode", { value: edit ? "edit" : "read" })
    oriel.controls.set("outline", { value: outlined })
    oriel.controls.set("edit-mode", { enabled: true, checked: edit })
  }

  /** Edit's editor takes the keyboard; Read's page, so the keys scroll it. */
  function focus(view: EditorView) {
    if (edit) view.focus()
    else view.scrollDOM.focus({ preventScroll: true })
  }

  /** The outline's rows; a click scrolls to its heading, and in Edit puts the caret there. */
  function list(view: EditorView, tree = syntaxTree(view.state)) {
    outline.replaceChildren(...headings(view.state, tree).map((heading) => {
      const row = document.createElement("button")
      row.textContent = heading.text
      row.style.paddingLeft = `${12 * heading.level}px`
      row.onclick = () => {
        const effects = EditorView.scrollIntoView(heading.from, { y: "start" })
        view.dispatch(edit ? { selection: { anchor: heading.from }, effects } : { effects })
        focus(view)
      }
      return row
    }))
  }

  /** Links in Read: `#` scrolls to its heading, http(s) opens a browser pane in a new tab (⌥ to the side), a
   *  relative path its file in the card (⌘ in a new tab, ⌥ to the side). */
  function follow(view: EditorView, event: MouseEvent) {
    const link = (event.target as Element).closest("a")
    if (!link) return false
    // In Edit too: a table's `href=""` link would load the page again and lose the edits.
    event.preventDefault()
    if (edit) return false
    const target = link.getAttribute("href") ?? ""
    if (target.startsWith("#")) {
      let anchor = target.slice(1)
      try {
        anchor = decodeURIComponent(anchor)
      } catch {
        // A `%` with no hex after it: the anchor as written.
      }
      const heading = headings(view.state, ensureSyntaxTree(view.state, view.state.doc.length, 200) ?? undefined)
        .find((each) => slug(each.text) === anchor.toLowerCase())
      if (heading) view.dispatch({ effects: EditorView.scrollIntoView(heading.from, { y: "start" }) })
    } else if (/^https?:/i.test(target)) {
      open(oriel, target, event.altKey ? "side" : "tab")
    } else if (target && !/^[a-z][a-z\d+.-]*:/i.test(target)) {
      const base = `file://${arg.split("/").map(encodeURIComponent).join("/")}`
      open(oriel, decodeURIComponent(new URL(target, base).pathname), how(event))
    }
    return true
  }

  // Read with the outline closed until the file shows.
  oriel.controls.set("mode", { value: "read" })
  oriel.controls.set("outline", { value: false })
  oriel.controls.set("edit-mode", { enabled: true, checked: false })
  let shown: Editor
  // Before the editor's own: ⌘F, ⌘G and ⇧⌘G in Read show Edit, where the search panel is.
  for (const name of ["find", "findNext", "findPrevious"] as const) {
    keep(oriel.on(name, () => shown && !edit && present(shown.view, true, outlined)))
  }
  shown = await editor(place, [
    // Front matter as YAML, not as a rule and a heading.
    yamlFrontmatter({ content: markdown({ base: markdownLanguage }) }),
    syntaxHighlighting(look),
    modeClass,
    blockField,
    livePreview,
    editable.of(mode(false)),
    EditorView.lineWrapping,
    EditorView.domEventHandlers({ click: (event, view) => follow(view, event) }),
    // Prose in the system font at the mockup's 14 pt (the app's 13 pt text size plus one), over the shared monospace.
    Prec.highest(EditorView.theme({
      "&": { fontSize: "calc(var(--font-size) + 1px)" },
      ".cm-scroller": { fontFamily: "system-ui", lineHeight: "1.55", outline: "none" },
      ".cm-content": { boxSizing: "border-box", maxWidth: "640px", margin: "0 auto", padding: "28px 24px 48px" },
      "&.cm-reading .cm-activeLine": { background: "none" },
      ".cm-frontmatter, .cm-frontmatter *": {
        fontFamily: "ui-monospace, monospace", fontSize: "12px", color: "var(--dim)",
      },
    })),
    EditorView.updateListener.of((update) => {
      // Also as the background parse reaches more headings.
      if (outlined && (update.docChanged || syntaxTree(update.startState) !== syntaxTree(update.state))) {
        list(update.view)
      }
    }),
  ], pane)

  // None when the file is too large to show: the info view is there instead, and Edit Mode does nothing.
  if (!shown) {
    oriel.controls.set("edit-mode", { enabled: false })
    return undefined
  }
  const { view, land } = shown
  // Copy in Read, whose keyboard is on the scroller: the source of the selection, also of lines not drawn (Select
  // All's selection reaches past the editor).
  const copy = (event: ClipboardEvent) => {
    const text = edit || event.defaultPrevented ? undefined : copied(view)
    if (text === undefined) return
    event.clipboardData?.setData("text/plain", text)
    event.preventDefault()
  }
  document.addEventListener("copy", copy)
  keep(() => document.removeEventListener("copy", copy))
  keep(oriel.on("control", ({ id, value }) => {
    if (id === "mode") present(view, value === "edit", outlined)
    else if (id === "outline") present(view, edit, value === true)
    else if (id === "edit-mode") present(view, !edit, outlined)
  }))
  // A linked open at a line (a diff's): Edit, with the caret there (`editor`). Back's landing is a path.
  present(view, Number(place.at) >= 1, false)
  // The app gives the card the keyboard: after the editor's own handler, Read's page takes it.
  const take = () => focus(view)
  addEventListener("focus", take)
  keep(() => removeEventListener("focus", take))
  return (at) => {
    if (Number(at) >= 1 && !edit) present(view, true, outlined)
    land(at)
  }
}
