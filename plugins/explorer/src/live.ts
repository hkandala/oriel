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
      if (node.name !== "Paragraph" && node.name !== "LinkReference") return containers.includes(node.name)
      // A footnote's definition is a paragraph's line, or a definition when its text is an address.
      for (let at = state.doc.lineAt(node.from); ; at = state.doc.line(at.number + 1)) {
        const key = footnote.exec(at.text)?.[1]
        if (key && !notes.has(key)) notes.set(key, { n: notes.size + 1, from: at.from })
        if (at.to >= node.to) break
      }
      const name = node.node.getChild("LinkLabel"), url = node.node.getChild("URL")
      const key = node.name === "LinkReference" && name ? label(state.sliceDoc(name.from, name.to)) : ""
      if (key && !key.startsWith("^") && url && !links.has(key)) {
        links.set(key, state.sliceDoc(url.from, url.to))
      }
      return false
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
  /** `indent`: the list items' indent around it, in em. */
  constructor(readonly source: string, readonly indent: number) {
    super()
  }
  eq(other: Block) {
    return other.source === this.source && other.indent === this.indent
  }
  toDOM(view: EditorView) {
    const block = Object.assign(document.createElement("div"), { className: "cm-md-block" })
    block.style.marginLeft = `${this.indent}em`
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

/** An element drawn in place of its source: a soft break's space, an entity's character, a thematic break's line, a
 *  `<br>`, a footnote's number. */
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
const space = Decoration.replace({ widget: new Html(" ") })

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
        const tag = name === "HTMLBlock" ? /^<([a-z][\w-]*)/i.exec(state.sliceDoc(node.from, node.to))?.[1] : undefined
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
          // In a list item: at its text, the source without the indent its lines share (four spaces or a tab would
          // make it code).
          const source = state.sliceDoc(from, to)
          const indent = source.split("\n").filter((each) => each.trim()).map((each) => /^[ \t]*/.exec(each)?.[0] ?? "")
            .reduce((common, each) => (each.startsWith(common) ? common : common.startsWith(each) ? each : ""))
          const widget = new Block(source.replaceAll(new RegExp(`^${indent}`, "gm"), ""), depth(node.node) * INDENT)
          ranges.push(Decoration.replace({ widget, block: true }).range(from, to))
        }
        return false
      }
      if (name === "LinkReference" && footnote.test(state.sliceDoc(from, to))) return false
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
        // Soft breaks are spaces, so the paragraph flows: not at the caret's lines, after a hard break (two spaces or
        // an unescaped backslash), nor before a footnote's definition.
        const first = doc.lineAt(node.from).number, last = doc.lineAt(node.to).number
        for (let n = first; n < last; n++) {
          const line = doc.line(n), next = doc.line(n + 1)
          if (touches(lines, line.from, next.to)) continue
          if (/(?: {2}|(?<!\\)(?:\\\\)*\\)$/.test(line.text) || footnote.test(next.text)) continue
          const start = next.from + (/^[ \t>]*/.exec(next.text)?.[0].length ?? 0)
          // A break in what the preview hides (a link's address, a tag, a comment) draws no space.
          const hidden = ["URL", "LinkMark", "LinkTitle", "HTMLTag", "Comment"]
            .includes(syntaxTree(state).resolveInner(line.to, -1).name)
          ranges.push((hidden ? Decoration.replace({}) : space).range(line.from + line.text.trimEnd().length, start))
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
  // A selection that keeps its lines (a drag in Read, a move in one line) changes nothing here.
  update: (set, tr) =>
    tr.docChanged || switched(tr.startState, tr.state) || changed(tr.startState, tr.state)
      || (tr.selection && JSON.stringify(active(tr.startState)) !== JSON.stringify(active(tr.state)))
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
    return other.text === this.text && other.width === this.width
      && JSON.stringify(other.task) === JSON.stringify(this.task)
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

const rule = Decoration.replace({ widget: new Html(`<span class="cm-md-hr"></span>`) })
const lineBreak = Decoration.widget({ widget: new Html("<br>") })

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

/** A link's address as the page follows it: without the `<>` of `[a](<my file.md>)` (Lezer's URL holds them), and
 *  GFM's bare `www.` and e-mail addresses with their scheme. */
function target(raw: string) {
  const url = raw.replace(/^<(.*)>$/s, "$1")
  return /^www\./i.test(url) ? `http://${url}` : /^[^\s/:@<>]+@[^\s/@<>]+\.[^\s/@<>]+$/.test(url) ? `mailto:${url}` : url
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
  /** Hides from `a` to `b`, line by line: a plugin may not replace a line break (the state field joins lines). */
  const conceal = (a: number, b: number) => {
    for (let at = a; at < b; at = doc.lineAt(at).to + 1) {
      const end = Math.min(b, doc.lineAt(at).to)
      if (end > at) ranges.push(hide.range(at, end))
    }
  }
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
            // A footnote's reference: a raised number that links to its definition (drawn with its line).
            const definition = state.sliceDoc(node.to, node.to + 1) === ":" && footnote.test(doc.lineAt(node.from).text)
            const href = `#fn:${encodeURIComponent(text.slice(1))}`
            const widget = new Html(`<sup class="cm-md-fnref"><a href="${href}">${note.n}</a></sup>`)
            if (off && !definition) ranges.push(Decoration.replace({ widget }).range(node.from, node.to))
            return false
          }
          // A reference's address by its label, or by its text (`[text][]`, `[text]`); none is no link but text.
          const href = url ? slice(url) : links.get(label(ref && ref.to - ref.from > 2 ? slice(ref) : text))
          if (!href) return
          if (textTo > textFrom) ranges.push(link(href).range(textFrom, textTo))
          else if (off) {
            // An image with no alt text: its address is the link, as markdown-it's rule draws it.
            const shown = md.utils.escapeHtml(target(href))
            ranges.push(Decoration.replace({ widget: new Html(`<a href="${shown}">${shown}</a>`) }).range(node.from, node.to))
            return
          }
          if (off) conceal(node.from, textFrom), conceal(textTo, node.to)
          return
        }
        if (name === "Autolink") {
          const url = node.node.getChild("URL")
          if (url) ranges.push(link(slice(url)).range(url.from, url.to))
          if (url && !raw(node.from)) ranges.push(hide.range(node.from, url.from), hide.range(url.to, node.to))
          return false
        }
        // GFM's bare address, also a footnote's text.
        if (name === "URL" && !["Link", "Image", "LinkReference"].includes(parent?.name ?? "")
          || (name === "URL" && parent?.name === "LinkReference" && footnote.test(doc.lineAt(node.from).text))) {
          ranges.push(link(slice(node)).range(node.from, node.to))
        }
        if (name === "Paragraph" || name === "LinkReference") {
          // A footnote's definition: its number in place of its label, in smaller secondary text.
          for (const each of shown(node)) {
            const match = /^([ \t>]*)\[\^([^\]\s]+)\]:/.exec(each.text), note = match && notes.get(match[2])
            if (!match || !note) continue
            ranges.push(line("cm-md-footnote").range(each.from))
            const at = each.from + match[1].length, widget = new Html(`<span class="cm-md-fn">${note.n}.</span>`)
            if (!raw(at)) ranges.push(Decoration.replace({ widget }).range(at, past(each.from + match[0].length)))
          }
        }
        if (name === "Blockquote") {
          // A bar for each quote around the line (markdown.css), the text after the last.
          const nested = node.node.getChildren("Blockquote")
          let quotes = 0
          for (let at: SyntaxNode | null = node.node; at; at = at.parent) quotes += Number(at.name === "Blockquote")
          const style = `--quotes: ${quotes}`
          for (const each of shown(node)) {
            if (nested.some((quote) => within(quote, each.from))) continue
            ranges.push(Decoration.line({ class: "cm-md-quote", attributes: { style } }).range(each.from))
          }
        }
        if (name === "FencedCode" || name === "CodeBlock") {
          const first = doc.lineAt(node.from).number, last = doc.lineAt(node.to).number
          // The fences' lines: a block not closed yet has only its opening one.
          const fences = new Set(node.node.getChildren("CodeMark").map((mark) => doc.lineAt(mark.from).number))
          let quoted = false
          for (let at = parent; at; at = at.parent) quoted ||= at.name === "Blockquote"
          for (const each of shown(node)) {
            const n = each.number, fence = fences.has(n) && !raw(each.from)
            const edge = `${n === first ? " cm-md-pre-first" : ""}${n === last ? " cm-md-pre-last" : ""}`
            ranges.push(line(`cm-md-pre${edge}${fence ? " cm-md-fence" : ""}`).range(each.from))
            if (fence && each.to > each.from) ranges.push(hide.range(each.from, each.to))
            // In a quote, the quote's marks.
            const marks = quoted && !fence && !raw(each.from) ? /^(?:[ \t]*>[ \t]?)+/.exec(each.text)?.[0].length : undefined
            if (marks) ranges.push(hide.range(each.from, each.from + marks))
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
          if (name === "Entity") {
            const widget = new Html(md.utils.escapeHtml(md.utils.unescapeAll(slice(node))))
            ranges.push(Decoration.replace({ widget }).range(node.from, node.to))
          }
          if (name === "HorizontalRule") ranges.push(rule.range(node.from, node.to))
        }
        if (name === "Comment" && !touches(lines, node.from, node.to)) conceal(node.from, node.to)
        if (name === "HTMLTag") {
          // An inline element drawn as itself: its tags hidden off the caret's lines, its text in it.
          const tag = slice(node), open = /^<([a-z][\w-]*)([^>]*?)\s*>$/i.exec(tag)
          const element = open?.[1].toLowerCase()
          if (element === "br" && !raw(node.from)) conceal(node.from, node.to), ranges.push(lineBreak.range(node.to))
          if (!element || !phrasing.has(element) || open?.[2].endsWith("/")) return
          // Its close: the first at its own depth among the tags of that name after it.
          const opens = new RegExp(`^<${element}[\\s>]`, "i"), closes = new RegExp(`^</${element}\\s*>$`, "i")
          let close = node.node.nextSibling
          for (let level = 0; close; close = close.nextSibling) {
            if (close.name !== "HTMLTag") continue
            if (opens.test(slice(close))) level++
            else if (closes.test(slice(close)) && level-- === 0) break
          }
          if (!close) return
          const href = element === "a" && open ? /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')/i.exec(open[2]) : undefined
          const attributes = href ? { href: target(href[1] ?? href[2]) } : undefined
          const mark = Decoration.mark({ tagName: element, attributes })
          if (close.from > node.to) ranges.push(mark.range(node.to, close.from))
          if (!touches(lines, node.from, close.to)) conceal(node.from, node.to), conceal(close.from, close.to)
        }
        if (name === "ListItem") {
          // The item's lines after its first (a second paragraph, a code block, the caret's paragraph) hang at its
          // text, their indent hidden; a nested list's lines are its own. A quote's or a code block's line moves whole,
          // with its bars or its fill (in a quote around the list, a code line's fill stays: the bars move not).
          const mark = node.node.getChild("ListMark")
          if (!mark) return
          const head = doc.lineAt(mark.from), width = depth(node.node) * INDENT
          const column = past(mark.to) - head.from
          const nested = [...node.node.getChildren("BulletList"), ...node.node.getChildren("OrderedList")]
          const code = [...node.node.getChildren("FencedCode"), ...node.node.getChildren("CodeBlock")]
          const quotes = node.node.getChildren("Blockquote")
          let quoted = false
          for (let at = node.node.parent; at; at = at.parent) quoted ||= at.name === "Blockquote"
          for (const each of shown(node)) {
            if (each.number <= head.number || !/[^\s>]/.test(each.text)) continue
            if (nested.some((list) => within(list, each.from))) continue
            const own = raw(each.from), hang = `${own ? width - 1 : width}em`
            const quote = quotes.some((block) => within(block, each.from))
            ranges.push((quote || (!quoted && code.some((block) => within(block, each.from)))
              ? Decoration.line({ attributes: { style: `margin-left: ${hang}` } })
              : Decoration.line({ class: "cm-md-hang", attributes: { style: `--hang: ${hang}` } })).range(each.from))
            // The spaces after any quote marks around the list (hidden with their own space), up to the item's text.
            const lead = quote ? /^()([ \t]*)/ : /^((?:[ \t]*>[ \t]?)*)([ \t]*)/
            const [, marks = "", spaces = ""] = lead.exec(each.text) ?? []
            const indent = Math.min(column - marks.length, spaces.length), at = each.from + marks.length
            if (!own && indent > 0) ranges.push(hide.range(at, at + indent))
          }
        }
        if (name === "ListMark" && parent?.name === "ListItem") {
          const each = doc.lineAt(node.from)
          const width = depth(parent) * INDENT
          // On the caret's line the mark shows where the bullet was, its text a little to the right.
          const style = raw(node.from) ? `--hang: ${width - 1}em` : `--hang: ${width}em; text-indent: -${width}em`
          ranges.push(Decoration.line({ class: "cm-md-hang", attributes: { style } }).range(each.from))
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
