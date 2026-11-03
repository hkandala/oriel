// The Markdown place's live preview (markdown.ts): CodeMirror's lines drawn as rendered Markdown, the same in Read and
// Edit but for the marks of the caret's lines in Edit. What crosses a line (a paragraph's soft breaks, a setext
// heading's underline) or replaces whole lines (tables, HTML blocks, reference definitions) lives in a state field; the
// rest is drawn per viewport.
import { HighlightStyle, syntaxHighlighting, syntaxTree } from "@codemirror/language"
import { Annotation, type EditorState, type Range, StateField } from "@codemirror/state"
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate, WidgetType } from "@codemirror/view"
import type { SyntaxNode } from "@lezer/common"
import { tags } from "@lezer/highlight"
import MarkdownIt from "markdown-it"

const md = new MarkdownIt({ html: true, linkify: true })
// Images are not loaded: their alt text links to them, as in a Markdown image's own line.
md.renderer.rules.image = (tokens, i) => {
  const { escapeHtml } = md.utils
  const src = String(tokens[i].attrGet("src") ?? "")
  return `<a href="${escapeHtml(src)}">${escapeHtml(tokens[i].content || src)}</a>`
}

/** The mode is the view's `editable`: Edit when it is, and the caret's lines show their marks. */
export const editing = (state: EditorState) => state.facet(EditorView.editable)
export const switched = (start: EditorState, now: EditorState) => editing(start) !== editing(now)
/** The nodes that hold blocks: the walks over the document's blocks go into these only. */
export const containers = ["Document", "Blockquote", "BulletList", "OrderedList", "ListItem"]

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
const changed = (start: EditorState, now: EditorState) => syntaxTree(start) !== syntaxTree(now)

/** A reference's label as CommonMark matches it: no brackets, case and runs of spaces ignored. */
const label = (text: string) => text.replace(/^\[|\]$/g, "").trim().replace(/\s+/g, " ").toLowerCase()
/** A footnote's definition at a line's start (`[^note]: …`), after any quote marks or indent. */
const footnote = /^[ \t>]*\[\^([^\]\s]+)\]:/

/** The document's link definitions (label to address) and footnotes (label to number and place, in order). */
type References = { links: Map<string, string>; notes: Map<string, { n: number; from: number }> }
function references(state: EditorState): References {
  const links = new Map<string, string>(), notes = new Map<string, { n: number; from: number }>()
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name === "LinkReference") {
        const name = node.node.getChild("LinkLabel"), url = node.node.getChild("URL")
        const key = name && label(state.sliceDoc(name.from, name.to))
        if (key && url && !links.has(key)) links.set(key, state.sliceDoc(url.from, url.to).replace(/^<|>$/g, ""))
        return false
      }
      if (node.name === "Paragraph") {
        for (let at = state.doc.lineAt(node.from); ; at = state.doc.line(at.number + 1)) {
          const key = footnote.exec(at.text)?.[1]
          if (key && !notes.has(key)) notes.set(key, { n: notes.size + 1, from: at.from })
          if (at.to >= node.to) break
        }
        return false
      }
      return containers.includes(node.name)
    },
  })
  return { links, notes }
}
export const referenceField = StateField.define<References>({
  create: references,
  update: (refs, tr) => (tr.docChanged || changed(tr.startState, tr.state) ? references(tr.state) : refs),
})

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

/** Text in place of source: a soft break's space, an entity's character. */
class Glyph extends WidgetType {
  constructor(readonly text: string) {
    super()
  }
  eq(other: Glyph) {
    return other.text === this.text
  }
  toDOM() {
    return Object.assign(document.createElement("span"), { textContent: this.text })
  }
}
const space = Decoration.replace({ widget: new Glyph(" ") })

/** The blocks drawn whole or hidden unless the caret is in them (tables, HTML blocks, comments, link definitions), and
 *  the line breaks that do not draw (a paragraph's soft breaks, a setext heading's underline): block widgets and
 *  replaced line breaks live in the state, not a plugin.
 *  ponytail: walks the document's blocks at each change of the caret; per viewport if long files lag. */
function blocks(state: EditorState): DecorationSet {
  const ranges: Range<Decoration>[] = []
  const lines = active(state), doc = state.doc
  /** The end of the blank line after `to`, when there is one: a hidden block takes it along, so no double gap stays. */
  const blank = (to: number) => {
    const next = to < doc.length ? doc.lineAt(to + 1) : undefined
    return next && !next.text.trim() && next.number < doc.lines ? next.to : to
  }
  /** An HTML element opened in one top-level block and closed in a later one (`<details>`, a blank line, then text)
   *  draws whole, up to here. */
  let skip = -1
  syntaxTree(state).iterate({
    enter(node) {
      const name = node.name
      if (node.from <= skip) return false
      const from = doc.lineAt(node.from).from
      let to = doc.lineAt(node.to).to
      if (name === "Table" || name === "HTMLBlock") {
        const tag = name === "HTMLBlock" && node.node.parent?.name === "Document"
          ? /^<([a-z][\w-]*)/i.exec(state.sliceDoc(node.from, node.to))?.[1] : undefined
        const close = tag && new RegExp(`</${tag}\\s*>`, "i")
        if (close && !close.test(state.sliceDoc(node.from, node.to))) {
          for (let next = node.node.nextSibling; next; next = next.nextSibling) {
            if (next.name === "HTMLBlock" && close.test(state.sliceDoc(next.from, next.to))) {
              to = skip = doc.lineAt(next.to).to
              break
            }
          }
        }
        if (!touches(lines, from, to)) {
          ranges.push(Decoration.replace({ widget: new Block(state.sliceDoc(from, to)), block: true }).range(from, to))
        }
        return false
      }
      if (name === "CommentBlock" || name === "LinkReference") {
        to = blank(to)
        if (!touches(lines, from, to)) ranges.push(Decoration.replace({ block: true }).range(from, to))
        return false
      }
      if (/^SetextHeading\d$/.test(name)) {
        const underline = doc.lineAt(node.to)
        if (!touches(lines, from, to)) ranges.push(Decoration.replace({}).range(doc.line(underline.number - 1).to, to))
        return false
      }
      if (name === "Paragraph") {
        // Soft breaks are spaces, so the paragraph flows: not after a hard break, nor before a footnote's definition.
        const first = doc.lineAt(node.from).number, last = doc.lineAt(node.to).number
        if (touches(lines, from, to)) return false
        for (let n = first; n < last; n++) {
          const line = doc.line(n), next = doc.line(n + 1)
          if (/(?: {2}|\\)$/.test(line.text) || footnote.test(next.text)) continue
          const start = next.from + (/^[ \t>]*/.exec(next.text)?.[0].length ?? 0)
          ranges.push(space.range(line.from + line.text.trimEnd().length, start))
        }
        return false
      }
      return containers.includes(name)
    },
  })
  return Decoration.set(ranges, true)
}
const blockField = StateField.define<DecorationSet>({
  create: blocks,
  update: (set, tr) =>
    tr.docChanged || tr.selection || switched(tr.startState, tr.state) || changed(tr.startState, tr.state)
      ? blocks(tr.state) : set,
  provide: (field) => EditorView.decorations.from(field),
})

/** A task's box ticked by a click: Read saves it (`show`). */
export const ticked = Annotation.define<boolean>()

/** A list item's bullet, number or task box, at the end of its depth's indent: the text and its wrapped lines start
 *  after it. A box is `marker` characters after the item's line start, and a click ticks it (a writable file). */
class Bullet extends WidgetType {
  constructor(readonly text: string, readonly width: number,
    readonly task?: { checked: boolean; marker: number; label: string }) {
    super()
  }
  eq(other: Bullet) {
    return other.text === this.text && other.width === this.width && other.task?.checked === this.task?.checked
      && other.task?.marker === this.task?.marker && other.task?.label === this.task?.label
  }
  toDOM(view: EditorView) {
    const bullet = Object.assign(document.createElement("span"), { className: "cm-md-bullet", textContent: this.text })
    bullet.style.minWidth = `${this.width - GAP}em`
    const task = this.task
    if (!task) return bullet
    const box = Object.assign(document.createElement("input"), {
      type: "checkbox", checked: task.checked, disabled: view.state.readOnly,
    })
    box.setAttribute("aria-label", task.label)
    // The file's character, not the box's own state: the widget draws again with it.
    box.onclick = (event) => {
      event.preventDefault()
      const at = view.posAtDOM(bullet) + task.marker + 1
      view.dispatch({ changes: { from: at, to: at + 1, insert: task.checked ? " " : "x" }, annotations: ticked.of(true) })
    }
    bullet.append(box)
    return bullet
  }
}

/** An element drawn in place of its source: a thematic break's line, a `<br>`, a footnote's number. */
class Html extends WidgetType {
  constructor(readonly html: string) {
    super()
  }
  eq(other: Html) {
    return other.html === this.html
  }
  toDOM() {
    return Object.assign(document.createElement("span"), { innerHTML: this.html })
  }
  ignoreEvent() {
    return false
  }
}
const rule = Decoration.replace({ widget: new Html(`<span class="cm-md-hr"></span>`) })
const lineBreak = Decoration.replace({ widget: new Html("<br>") })

const hide = Decoration.replace({})
const line = (className: string) => Decoration.line({ class: className })
const frontmatter = Decoration.mark({ class: "cm-frontmatter" })
const code = Decoration.mark({ class: "cm-md-code" })
// The marks of an element, hidden off the caret's lines: a heading's `#`, emphasis, code ticks. Links hide their own.
const marks = new Set(["HeaderMark", "EmphasisMark", "StrikethroughMark", "CodeMark"])
const kept = new Set(["FencedCode", "SetextHeading1", "SetextHeading2"])
/** The inline HTML elements drawn as themselves; others show as written. */
const phrasing = new Set(["a", "abbr", "b", "cite", "code", "del", "em", "i", "ins", "kbd", "mark", "q", "s", "samp",
  "small", "span", "strong", "sub", "sup", "u", "var"])
/** Each list depth's indent, and the space between a bullet and its text, in em. */
const INDENT = 1.5
const GAP = 0.4

/** A link's address as the page follows it: GFM's bare `www.` and e-mail addresses get their scheme. */
const target = (url: string) =>
  /^www\./i.test(url) ? `http://${url}` : /^[^\s/:@<>]+@[^\s/@<>]+\.[^\s/@<>]+$/.test(url) ? `mailto:${url}` : url
/** An entity's character. */
function character(entity: string) {
  const text = document.createElement("textarea")
  text.innerHTML = entity
  return text.value
}
/** A list item's depth: 1 at the top. */
function depth(item: SyntaxNode) {
  let n = 0
  for (let at: SyntaxNode | null = item; at; at = at.parent) n += Number(/^(Bullet|Ordered)List$/.test(at.name))
  return n
}

/** The rendered look of the visible lines: marks hidden off the caret's lines, line styles for headings, lists,
 *  quotes and code, links as links. */
function preview(view: EditorView): DecorationSet {
  const { state } = view
  const { doc } = state
  const ranges: Range<Decoration>[] = []
  const lines = active(state)
  const { links, notes } = state.field(referenceField)
  /** The line of `pos` is a caret's. */
  const raw = (pos: number) => touches(lines, pos, pos)
  /** After one space at `pos`: a mark takes its space along. */
  const past = (pos: number) => (state.sliceDoc(pos, pos + 1) === " " ? pos + 1 : pos)
  const slice = (node: { from: number; to: number }) => state.sliceDoc(node.from, node.to)
  const link = (href: string) => Decoration.mark({ tagName: "a", attributes: { href: target(href) } })
  /** The visible range walked now. */
  let from = 0, to = 0
  /** The line starts at or in `node`, from its first line on. */
  const within = (node: { from: number; to: number }, at: number) => doc.lineAt(node.from).from <= at && at <= node.to
  /** Each line of a node that is in view. */
  const shown = (node: { from: number; to: number }) => {
    const first = doc.lineAt(Math.max(node.from, from)).number
    const last = doc.lineAt(Math.min(node.to, to)).number
    return Array.from({ length: last - first + 1 }, (_, i) => doc.line(first + i))
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
          ranges.push(Decoration.line({ class: `cm-md-h${heading}`, attributes }).range(doc.lineAt(node.from).from))
        }
        if (name === "InlineCode") ranges.push(code.range(node.from, node.to))
        if (name === "Link" || name === "Image") {
          const marks = node.node.getChildren("LinkMark"), url = node.node.getChild("URL")
          const ref = node.node.getChild("LinkLabel")
          const textFrom = marks[0]?.to ?? node.from, textTo = marks[1]?.from ?? node.to
          const text = state.sliceDoc(textFrom, textTo), off = !touches(lines, node.from, node.to)
          const note = name === "Link" && !url && !ref && text.startsWith("^") ? notes.get(text.slice(1)) : undefined
          if (note) {
            // A footnote: its definition's number at the line's start, its reference a superscript link to it.
            const definition = footnote.test(doc.lineAt(node.from).text) && state.sliceDoc(node.to, node.to + 1) === ":"
            if (definition) ranges.push(line("cm-md-footnote").range(doc.lineAt(node.from).from))
            const html = definition ? `<span class="cm-md-fn">${note.n}.</span>`
              : `<sup class="cm-md-fnref"><a href="#fn:${encodeURIComponent(text.slice(1))}">${note.n}</a></sup>`
            const end = definition ? past(node.to + 1) : node.to
            if (off) ranges.push(Decoration.replace({ widget: new Html(html) }).range(node.from, end))
            return false
          }
          // A reference's address by its label, or by its text (`[text][]`, `[text]`); none is no link but text.
          const href = url ? slice(url) : links.get(label(ref && ref.to - ref.from > 2 ? slice(ref) : text))
          if (!href) return
          if (textTo > textFrom) ranges.push(link(href).range(textFrom, textTo))
          if (off) ranges.push(hide.range(node.from, textFrom), hide.range(textTo, node.to))
          return
        }
        if (name === "Autolink") {
          const url = node.node.getChild("URL")
          if (url) ranges.push(link(slice(url)).range(url.from, url.to))
          if (url && !raw(node.from)) ranges.push(hide.range(node.from, url.from), hide.range(url.to, node.to))
          return false
        }
        // GFM's bare address.
        if (name === "URL" && parent?.name !== "LinkReference") ranges.push(link(slice(node)).range(node.from, node.to))
        if (name === "Blockquote") {
          // A bar for each quote around the line, the text after the last.
          const nested = node.node.getChildren("Blockquote")
          let quotes = 0
          for (let at: SyntaxNode | null = node.node; at; at = at.parent) quotes += Number(at.name === "Blockquote")
          const bars = Array.from({ length: quotes }, (_, i) =>
            `linear-gradient(var(--divider), var(--divider)) ${3 + i * 18}px 0 / 3px 100% no-repeat`)
          const style = `padding-left: ${quotes * 18}px; background: ${bars.join(", ")}`
          for (const each of shown(node)) {
            if (nested.some((quote) => within(quote, each.from))) continue
            ranges.push(Decoration.line({ class: "cm-md-quote", attributes: { style } }).range(each.from))
          }
        }
        if (name === "FencedCode" || name === "CodeBlock") {
          const first = doc.lineAt(node.from).number, last = doc.lineAt(node.to).number
          // The fences' lines: a block not closed yet has only its opening one.
          const fences = new Set(node.node.getChildren("CodeMark").map((mark) => doc.lineAt(mark.from).number))
          for (const each of shown(node)) {
            const n = each.number, fence = fences.has(n) && !raw(each.from)
            const edge = `${n === first ? " cm-md-pre-first" : ""}${n === last ? " cm-md-pre-last" : ""}`
            ranges.push(line(`cm-md-pre${edge}${fence ? " cm-md-fence" : ""}`).range(each.from))
            if (fence && each.to > each.from) ranges.push(hide.range(each.from, each.to))
            // An indented block's indent is its mark.
            const indent = name === "CodeBlock" && parent?.name === "Document" && !raw(each.from)
              ? /^(?: {1,4}|\t)/.exec(each.text)?.[0].length : undefined
            if (indent) ranges.push(hide.range(each.from, each.from + indent))
          }
          return false
        }
        if (!raw(node.from)) {
          // An escape's backslash, a hard break's backslash, an entity's name, an inline comment.
          if (name === "Escape" || (name === "HardBreak" && slice(node).startsWith("\\"))) {
            ranges.push(hide.range(node.from, node.from + 1))
          }
          if (name === "Entity") ranges.push(Decoration.replace({ widget: new Glyph(character(slice(node))) }).range(node.from, node.to))
          if (name === "Comment") ranges.push(hide.range(node.from, node.to))
          if (name === "HorizontalRule") ranges.push(rule.range(node.from, node.to))
        }
        if (name === "HTMLTag") {
          // An inline element drawn as itself: its tags hidden off the caret's lines, its text in it.
          const tag = slice(node), open = /^<([a-z][\w-]*)([^>]*?)\s*>$/i.exec(tag)
          const element = open?.[1].toLowerCase()
          if (element === "br" && !raw(node.from)) ranges.push(lineBreak.range(node.from, node.to))
          if (!element || !phrasing.has(element) || open?.[2].endsWith("/")) return
          let close = node.node.nextSibling
          while (close && !(close.name === "HTMLTag" && new RegExp(`^</${element}\\s*>$`, "i").test(slice(close)))) {
            close = close.nextSibling
          }
          if (!close) return
          const href = element === "a" && open ? /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')/i.exec(open[2]) : undefined
          const attributes = href ? { href: target(href[1] ?? href[2]) } : undefined
          if (close.from > node.to) ranges.push(Decoration.mark({ tagName: element, attributes }).range(node.to, close.from))
          if (!touches(lines, node.from, close.to)) ranges.push(hide.range(node.from, node.to), hide.range(close.from, close.to))
        }
        if (name === "ListItem") {
          // The item's lines after its first (a second paragraph, a code block, the caret's paragraph) hang at its
          // text, their indent hidden; a nested list's lines are its own.
          const mark = node.node.getChild("ListMark")
          if (!mark) return
          const head = doc.lineAt(mark.from), width = depth(node.node) * INDENT
          const column = past(mark.to) - head.from
          const nested = [...node.node.getChildren("BulletList"), ...node.node.getChildren("OrderedList")]
          for (const each of shown(node)) {
            if (each.number <= head.number || !/[^\s>]/.test(each.text)) continue
            if (nested.some((list) => within(list, each.from))) continue
            const own = raw(each.from)
            ranges.push(Decoration.line({ attributes: { style: `margin-left: ${own ? width - 1 : width}em` } }).range(each.from))
            const indent = Math.min(column, /^[ \t]*/.exec(each.text)?.[0].length ?? 0)
            if (!own && indent) ranges.push(hide.range(each.from, each.from + indent))
          }
        }
        if (name === "ListMark" && parent?.name === "ListItem") {
          const each = doc.lineAt(node.from)
          const width = depth(parent) * INDENT
          // On the caret's line the mark shows where the bullet was, its text a little to the right.
          const style = raw(node.from)
            ? `padding-left: calc(${width - 1}em + 6px)`
            : `padding-left: calc(${width}em + 6px); text-indent: -${width}em`
          ranges.push(Decoration.line({ class: "cm-md-li", attributes: { style } }).range(each.from))
          if (!raw(node.from)) {
            // A task's box takes its bullet's place; a number counts from the list's first.
            const marker = parent.getChild("Task")?.getChild("TaskMarker") ?? undefined
            const end = past(marker?.to ?? node.to)
            const task = marker && {
              checked: state.sliceDoc(marker.from + 1, marker.to - 1) !== " ", marker: marker.from - each.from,
              label: state.sliceDoc(end, each.to),
            }
            let text = "•"
            const list = parent.parent
            if (list?.name === "OrderedList") {
              let n = Number.parseInt(slice(list.firstChild?.getChild("ListMark") ?? node), 10)
              for (let item = list.firstChild; item && item.from < parent.from; item = item.nextSibling) n++
              text = `${n}.`
            }
            ranges.push(Decoration.replace({ widget: new Bullet(task ? "" : text, width, task) }).range(each.from, end))
          }
        }
        if (name === "QuoteMark" && !raw(node.from)) ranges.push(hide.range(node.from, past(node.to)))
        if (!marks.has(name) || !parent || kept.has(parent.name)) return
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
        || switched(update.startState, update.state) || changed(update.startState, update.state)) {
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
  { tag: [tags.url, tags.processingInstruction, tags.quote], color: "var(--dim)" },
  { tag: tags.monospace, fontFamily: "ui-monospace, monospace", fontSize: "0.9em" },
])

/** The live preview's extensions. */
export const live = [syntaxHighlighting(look), referenceField, blockField, livePreview]
