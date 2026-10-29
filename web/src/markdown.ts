// The Markdown card. Read shows the text rendered by markdown-it; Edit is the file's own text in CodeMirror, each
// mark hidden unless the caret is in its element. The outline lists the headings; row 2 picks the mode and the
// outline, and the page reports what it shows.
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { ensureSyntaxTree, HighlightStyle, syntaxHighlighting, syntaxTree } from "@codemirror/language"
import { Prec } from "@codemirror/state"
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view"
import { tags } from "@lezer/highlight"
import MarkdownIt from "markdown-it"
import { arg, at, receive, report } from "./lib/bridge"
import { editor, handle } from "./lib/editor"
import "./markdown/markdown.css"

const outline = document.createElement("nav")
const article = document.createElement("article")
const pane = document.createElement("main")
article.tabIndex = -1
// Shown once the file is: not beside the info view.
outline.hidden = true
pane.append(article)
document.body.append(outline, pane)

const md = new MarkdownIt({ html: true, linkify: true })
type Env = { ids: Map<string, number>; line: number }
/** A YAML front matter's end: Read leaves it out, the outline skips it. */
const front = (text: string) => /^---\n[\w-]+:[\s\S]*?\n---(?:\n|$)/.exec(text)?.[0].length ?? 0

/** The text as HTML, without its front matter, task boxes drawn as GitHub does. */
function render(text: string) {
  const start = front(text)
  const env: Env = { ids: new Map(), line: text.slice(0, start).split("\n").length }
  article.innerHTML = md.render(text.slice(start), env)
    .replace(/(<li>(?:<p>)?)\[([ xX])\] /g, (_, li, box) =>
      `${li}<input type="checkbox" disabled${box === " " ? "" : " checked"}> `)
}
// Headings get GitHub's ids, for `#` links, and their source line, for the outline.
md.renderer.rules.heading_open = (tokens, i, options, env: Env, self) => {
  const slug = tokens[i + 1].content.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s/g, "-")
  const n = env.ids.get(slug) ?? 0
  env.ids.set(slug, n + 1)
  tokens[i].attrSet("id", n ? `${slug}-${n}` : slug)
  tokens[i].attrSet("data-line", String((tokens[i].map?.[0] ?? 0) + env.line))
  return self.renderToken(tokens, i, options)
}

// Images are not loaded: their alt text links to them, as in the native variant.
md.renderer.rules.image = (tokens, i) => {
  const { escapeHtml } = md.utils
  const src = tokens[i].attrGet("src") ?? ""
  return `<a href="${escapeHtml(src)}">${escapeHtml(tokens[i].content || src)}</a>`
}

// Marks in Edit, hidden outside their element: a heading's `#`, emphasis, a link's brackets and address, code ticks.
const marks = new Set(["HeaderMark", "EmphasisMark", "StrikethroughMark", "LinkMark", "URL", "LinkTitle", "CodeMark"])
// A setext heading's underline stays: hidden, it would leave an empty line.
const shown = new Set(["FencedCode", "Autolink", "LinkReference", "SetextHeading1", "SetextHeading2"])

function hidden(view: EditorView): DecorationSet {
  const { state } = view
  const ranges = []
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter(node) {
        const parent = node.node.parent
        if (!marks.has(node.name) || !parent || shown.has(parent.name)) return
        // A bare address (GFM) is the text itself.
        if (node.name === "URL" && parent.name !== "Link" && parent.name !== "Image") return
        if (state.selection.ranges.some((range) => range.from <= parent.to && range.to >= parent.from)) return
        // A heading's mark takes its space along.
        const end = node.name === "HeaderMark" && state.sliceDoc(node.to, node.to + 1) === " " ? node.to + 1 : node.to
        ranges.push(Decoration.replace({}).range(node.from, end))
      },
    })
  }
  return Decoration.set(ranges, true)
}

const livePreview = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet
    constructor(view: EditorView) {
      this.decorations = hidden(view)
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet || update.viewportChanged
        || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        this.decorations = hidden(update.view)
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
)

const look = HighlightStyle.define([
  { tag: tags.heading1, fontSize: "1.6em", fontWeight: "600" },
  { tag: tags.heading2, fontSize: "1.3em", fontWeight: "600" },
  { tag: tags.heading3, fontSize: "1.1em", fontWeight: "600" },
  { tag: [tags.heading4, tags.heading5, tags.heading6, tags.strong], fontWeight: "600" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.link, color: "var(--accent)" },
  { tag: [tags.url, tags.processingInstruction, tags.quote], color: "var(--dim)" },
  { tag: tags.monospace, fontFamily: "ui-monospace, monospace", fontSize: "0.9em" },
])

let edit = false
let outlined = false
article.hidden = true
const view = await editor([
  markdown({ base: markdownLanguage }),
  syntaxHighlighting(look),
  livePreview,
  EditorView.lineWrapping,
  // Prose in the system font at the mockup's 14 pt (the app's 13 pt text size plus one), over the shared monospace.
  Prec.highest(EditorView.theme({
    "&": { fontSize: "calc(var(--font-size) + 1px)" },
    ".cm-scroller": { fontFamily: "system-ui", lineHeight: "1.55" },
    ".cm-content": { boxSizing: "border-box", maxWidth: "640px", margin: "0 auto", padding: "16px 24px 48px" },
  })),
  EditorView.updateListener.of((update) => {
    if (update.docChanged && !edit) render(update.state.doc.toString())
    // Also as the background parse reaches more headings.
    if (outlined && (update.docChanged || syntaxTree(update.startState) !== syntaxTree(update.state))) {
      list(update.view)
    }
  }),
], pane)

/** Shows Read or Edit and the outline or not, and tells the app. */
function show(view: EditorView, nowEdit: boolean, nowOutlined: boolean) {
  if (!nowEdit && (edit || !article.innerHTML)) render(view.state.doc.toString())
  edit = nowEdit
  outlined = nowOutlined
  article.hidden = edit
  view.dom.hidden = !edit
  outline.hidden = !outlined
  if (outlined) {
    ensureSyntaxTree(view.state, view.state.doc.length, 200)
    list(view)
  }
  ;(edit ? view : article).focus()
  report({ op: "markdown", edit, outline: outlined })
}

/** The outline's rows: the headings in the editor's syntax tree, at the top level, in lists and in quotes. */
function list(view: EditorView) {
  const { state } = view
  const rows: HTMLButtonElement[] = []
  const start = front(state.doc.sliceString(0, 10_000))
  syntaxTree(state).iterate({
    enter(node) {
      const level = /^(?:ATX|Setext)Heading(\d)$/.exec(node.name)?.[1]
      if (!level) return ["Document", "Blockquote", "BulletList", "OrderedList", "ListItem"].includes(node.name)
      if (node.from < start) return false
      const line = state.doc.lineAt(node.from)
      // The text between an ATX heading's marks, or above a setext heading's underline.
      const [first, last] = node.node.getChildren("HeaderMark")
      const text = node.name.startsWith("ATX")
        ? state.sliceDoc(first?.to ?? node.from, last?.from ?? node.to)
        : state.sliceDoc(node.from, first?.from ?? node.to)
      const row = document.createElement("button")
      row.textContent = text.trim() || line.text
      row.style.paddingLeft = `${12 * Number(level)}px`
      // Edit: the caret to the heading; Read: its element, by its source line.
      row.onclick = () => {
        if (!edit) return article.querySelector(`[data-line="${line.number}"]`)?.scrollIntoView()
        const effects = EditorView.scrollIntoView(line.from, { y: "start" })
        view.dispatch({ selection: { anchor: line.from }, effects })
        view.focus()
      }
      rows.push(row)
      return false
    },
  })
  outline.replaceChildren(...rows)
}

// Links in Read: `#` scrolls the page, http(s) opens the browser plugin, a relative path the plugin of its kind.
article.addEventListener("click", (event) => {
  const link = (event.target as Element).closest("a")
  if (!link) return
  // Also an empty address, which would load the page again and lose the edits.
  event.preventDefault()
  const href = link.getAttribute("href") ?? ""
  if (href.startsWith("#")) {
    document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView()
  } else if (/^https?:/i.test(href)) {
    report({ op: "open", kind: "browser", arg: href })
  } else if (href && !/^[a-z][a-z\d+.-]*:/i.test(href)) {
    const base = `file://${arg.split("/").map(encodeURIComponent).join("/")}`
    report({ op: "open", arg: decodeURIComponent(new URL(href, base).pathname) })
  }
})

// Undefined when the file is too large to show: the info view is there instead.
if (!view) {
  report({ op: "markdown", edit: false, outline: false })
} else {
  receive((message) => {
    if (message.op === "markdown") return show(view, message.edit, message.outline)
    // Find works in the text: Read hides it.
    if (message.op === "find" && !edit) show(view, true, outlined)
    handle(view, message)
  })
  // A linked open at a line (a diff's): Edit, with the caret there (`editor`).
  show(view, Boolean(at), false)
  // The app gives the card the keyboard: Read's page takes it; Edit's editor has it (`editor`).
  addEventListener("focus", () => edit || article.focus())
}
