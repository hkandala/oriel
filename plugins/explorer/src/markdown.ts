// The Markdown place: one CodeMirror view of the file in four modes. Read and Live Edit draw it as rendered Markdown (a
// live preview, live.ts): Read is the view not editable with every line drawn; Live Edit puts back the marks of the
// caret's lines, so a switch between them moves nothing on screen but the caret's line. Source draws the file as code
// cards do; Side by Side puts the rendered page beside Source (split.ts). The outline lists the headings; row 2 picks
// the mode and the outline (its toggle shows only while the file has a heading), and the page sets them when it
// changes them itself.
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { yamlFrontmatter } from "@codemirror/lang-yaml"
import { ensureSyntaxTree, syntaxTree, syntaxTreeAvailable } from "@codemirror/language"
import { closeSearchPanel } from "@codemirror/search"
import { Compartment, EditorState, Prec } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { code, type Editor, editor } from "./editor"
import { containers, editing, live, referenceField, ticked } from "./live"
import { how, open, type Place, type Reveal, symbols } from "./place"
import { sideBySide } from "./split"

type Mode = "read" | "live" | "source" | "split"
const MODES: Mode[] = ["read", "live", "source", "split"]
/** The card's mode, the last its Markdown pages showed: a page shown anew or again shows it. */
let cardMode: Mode | undefined

/** GitHub's anchor of a heading's text, for `#` links. */
const slug = (text: string) => text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s/g, "-")

/** Read: no text box for VoiceOver, an article; a drop changes nothing. Not read only: the editor's read only is
 *  the file's (`editor`), and a tick in Read writes. */
const markdownMode = (edit: boolean) => [
  EditorView.editable.of(edit),
  edit ? [] : [
    Prec.highest(EditorView.contentAttributes.of({ role: "article", "aria-readonly": "true" })),
    EditorView.domEventHandlers({ drop: (event) => (event.preventDefault(), true) }),
  ],
]
const modeClass = EditorView.editorAttributes.compute([EditorView.editable], (state) => ({
  class: editing(state) ? "" : "cm-reading",
}))
/** Read's and Live Edit's look, and Side by Side's page: prose in the system font at the mockup's 14 pt (the app's
 *  13 pt text size plus one), over the shared monospace, in a 640 pt column. */
const rendered = [
  live,
  modeClass,
  Prec.highest(EditorView.theme({
    "&": { fontSize: "calc(var(--font-size) + 1px)" },
    ".cm-scroller": { fontFamily: "system-ui", lineHeight: "1.55", outline: "none" },
    ".cm-content": { boxSizing: "border-box", maxWidth: "640px", margin: "0 auto", padding: "28px 24px 48px" },
    "&.cm-reading .cm-activeLine": { background: "none" },
    ".cm-frontmatter, .cm-frontmatter *": {
      fontFamily: "ui-monospace, monospace", fontSize: "12px", color: "var(--dim)",
    },
  })),
]
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

/** Every heading of the document: the background parse stops past the viewport. */
const all = (state: EditorState) => headings(state, ensureSyntaxTree(state, state.doc.length, 200) ?? undefined)

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
  const { ovvi, arg, keep, root } = place
  const outline = Object.assign(document.createElement("nav"), { className: "ovvi-sidebar" })
  const pane = document.createElement("main")
  // Shown once the file is: not beside the info view. Closed until the outline is on, then it slides.
  outline.hidden = true
  outline.toggleAttribute("data-closed", true)
  root.append(outline, pane)
  // The card's mode: as another Markdown page left it, else as row 2 kept it (a relaunch).
  const kept = ovvi.controls.get("mode") as Mode, first = cardMode ?? (MODES.includes(kept) ? kept : "read")
  let mode: Mode = "read"
  /** Every mode but Read edits; ⌘E goes back to the last one. */
  let edit = false
  let lastEdit: Mode = first === "read" ? "live" : first
  let outlined = false
  /** The file has a heading: the outline's toggle shows only then. */
  let titled = false
  const editable = new Compartment(), look = new Compartment()
  /** Side by Side's page, while it shows. */
  let split: ReturnType<typeof sideBySide> | undefined
  keep(() => split?.destroy())

  /** Shows the mode and the outline or not, and sets row 2 and Edit Mode to match. */
  function present(view: EditorView, now: Mode, nowOutlined: boolean) {
    const nowEdit = now !== "read", coded = (each: Mode) => each === "source" || each === "split"
    if (now !== mode) {
      // Read keeps no selection drawn, nor a search panel (its Replace would write).
      if (!nowEdit) closeSearchPanel(view)
      const selection = nowEdit ? undefined : { anchor: view.state.selection.main.head }
      const effects = [editable.reconfigure(markdownMode(nowEdit)), look.reconfigure(coded(now) ? source : rendered)]
      // A new look keeps the line at the top in place.
      if (coded(now) !== coded(mode)) {
        const top = view.lineBlockAtHeight(view.scrollDOM.scrollTop - view.documentPadding.top).from
        effects.push(EditorView.scrollIntoView(top, { y: "start" }))
      }
      view.dispatch({ selection, effects })
      split?.destroy()
      split = now === "split" ? sideBySide(view, pane, page) : undefined
    }
    mode = cardMode = now
    edit = nowEdit
    if (edit) lastEdit = mode
    outlined = nowOutlined && titled
    outline.hidden = false
    outline.toggleAttribute("data-closed", !outlined)
    if (outlined) list(view, all(view.state))
    focus(view)
    ovvi.controls.set("mode", { value: mode })
    ovvi.controls.set("outline", { value: outlined })
    ovvi.controls.set("edit-mode", { enabled: true, checked: edit })
  }

  /** An edit mode's editor takes the keyboard; Read's page, so the keys scroll it. */
  function focus(view: EditorView) {
    if (edit) view.focus()
    else view.scrollDOM.focus({ preventScroll: true })
  }

  /** The outline's toggle shows while the file has headings; with none, the outline closes. */
  function titles(view: EditorView, found: ReturnType<typeof headings>) {
    const now = found.length > 0
    if (now !== titled) {
      titled = now
      ovvi.controls.set("outline", { hidden: !titled })
      if (!titled && outlined) present(view, mode, false)
    }
    if (outlined) list(view, found)
  }

  /** The outline's rows; a click scrolls to its heading, and in an edit mode puts the caret there. */
  function list(view: EditorView, found: ReturnType<typeof headings>) {
    outline.replaceChildren(...found.map((heading) => {
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
    // In Live Edit too: a table's `href=""` link would load the page again and lose the edits.
    event.preventDefault()
    if (editing(view.state)) return false
    const target = link.getAttribute("href") ?? ""
    if (target.startsWith("#")) {
      let anchor = target.slice(1)
      try {
        anchor = decodeURIComponent(anchor)
      } catch {
        // A `%` with no hex after it: the anchor as written.
      }
      // A footnote's number links to its definition; a heading's anchor is GitHub's, `-1` on for a second of a name.
      const note = anchor.startsWith("fn:") ? view.state.field(referenceField).notes.get(anchor.slice(3)) : undefined
      const seen = new Map<string, number>()
      const heading = note ?? all(view.state).find((each) => {
        const base = slug(each.text), n = seen.get(base) ?? 0
        seen.set(base, n + 1)
        return (n ? `${base}-${n}` : base) === anchor.toLowerCase()
      })
      if (heading) view.dispatch({ effects: EditorView.scrollIntoView(heading.from, { y: "start" }) })
    } else if (/^https?:/i.test(target)) {
      open(ovvi, target, event.altKey ? "side" : "tab")
    } else if (target && !/^[a-z][a-z\d+.-]*:/i.test(target)) {
      const base = `file://${arg.split("/").map(encodeURIComponent).join("/")}`
      open(ovvi, decodeURIComponent(new URL(target, base).pathname), how(event))
    }
    return true
  }

  // The outline closed until the file shows.
  ovvi.controls.set("mode", { value: first })
  ovvi.controls.set("outline", { value: false })
  ovvi.controls.set("edit-mode", { enabled: true, checked: false })
  symbols(ovvi, ["chevron.left", "chevron.right"])
  let shown: Editor
  /** The saves of Read's ticks, one after the other: a save under way skips a second one. */
  let ticks = Promise.resolve()
  // Before the editor's own: ⌘F, ⌘G and ⇧⌘G in Read show the last edit mode, where the search panel is; ⌥⌘F too.
  const finding = () => shown && !edit && present(shown.view, lastEdit, outlined)
  for (const name of ["find", "findNext", "findPrevious"] as const) ovvi.on(name, finding)
  const replacing = (event: KeyboardEvent) =>
    place.shown() && event.code === "KeyF" && event.metaKey && event.altKey && finding()
  addEventListener("keydown", replacing)
  keep(() => removeEventListener("keydown", replacing))
  // Front matter as YAML, not as a rule and a heading.
  const language = yamlFrontmatter({ content: markdown({ base: markdownLanguage }) })
  const links = EditorView.domEventHandlers({ click: (event, view) => follow(view, event) })
  /** Source: the file as code cards draw it. */
  const source = [code, Prec.highest(EditorView.theme({ ".cm-content": { paddingBottom: "48px" } }))]
  /** Side by Side's page: Read's look, its links and its ticks. */
  const page = [language, rendered, markdownMode(false), EditorView.lineWrapping, links]
  shown = await editor(place, [
    language,
    look.of(rendered),
    editable.of(markdownMode(false)),
    EditorView.lineWrapping,
    links,
    EditorView.updateListener.of((update) => {
      split?.follow(update)
      // A box ticked in Read is saved at once, as the card's ⌘S, after any save under way; in an edit mode it waits
      // for ⌘S as any edit.
      if (!edit && update.transactions.some((tr) => tr.annotation(ticked))) ticks = ticks.then(() => shown?.save())
      // Also as the background parse reaches more headings.
      if (update.docChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        const found = headings(update.state)
        // No heading in a tree cut short says nothing: its headings can be below the parsed part.
        if (found.length || syntaxTreeAvailable(update.state)) titles(update.view, found)
      }
    }),
  ], pane)

  // None when the file is too large to show: the info view is there instead, and Edit Mode does nothing.
  if (!shown) {
    ovvi.controls.set("edit-mode", { enabled: false })
    ovvi.controls.set("mode", { hidden: true })
    return undefined
  }
  const { view, land } = shown
  // Copy in Read, whose keyboard is on the scroller: the source of the selection, also of lines not drawn (Select
  // All's selection reaches past the editor).
  const copy = (event: ClipboardEvent) => {
    const text = edit || event.defaultPrevented || !place.shown() ? undefined : copied(view)
    if (text === undefined) return
    event.clipboardData?.setData("text/plain", text)
    event.preventDefault()
  }
  document.addEventListener("copy", copy)
  keep(() => document.removeEventListener("copy", copy))
  ovvi.on("control", ({ id, value }) => {
    if (id === "mode" && MODES.includes(value as Mode)) present(view, value as Mode, outlined)
    else if (id === "outline") present(view, mode, value === true)
    else if (id === "edit-mode") present(view, edit ? "read" : lastEdit, outlined)
  })
  titles(view, all(view.state))
  // A linked open at a line (a diff's): an edit mode, with the caret there (`editor`). Back's landing is a path.
  present(view, Number(place.at) >= 1 && first === "read" ? lastEdit : first, false)
  // A kept page shown again (Back, Forward, a link) takes the card's mode.
  ovvi.on("place", () => cardMode && present(view, cardMode, outlined))
  // The app gives the card the keyboard: after the editor's own handler, Read's page takes it.
  const take = () => place.shown() && focus(view)
  addEventListener("focus", take)
  keep(() => removeEventListener("focus", take))
  return (at) => {
    if (Number(at) >= 1 && !edit) present(view, lastEdit, outlined)
    land(at)
  }
}
