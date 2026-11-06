// The Markdown place: one CodeMirror view of the file in two modes, each locked or not. Rich Text draws it as rendered
// Markdown (a live preview, live.ts): locked, the view is not editable and every line is drawn; unlocked, the marks of
// the caret's lines come back, so the lock moves nothing on screen but the caret's line. Source draws the file as code
// cards do, with the rendered page beside it, folded until the user shows it (split.ts); locked, neither edits. The
// outline lists the headings; row 2 picks the mode, the lock and the outline (its toggle shows only while the file has a
// heading), and the page sets them when it changes them itself.
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { yamlFrontmatter } from "@codemirror/lang-yaml"
import { ensureSyntaxTree, syntaxTree, syntaxTreeAvailable } from "@codemirror/language"
import { closeSearchPanel } from "@codemirror/search"
import { Compartment, EditorState, Prec } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { code, type Editor, editor, selected } from "./editor"
import { containers, editing, live, referenceField, ticked } from "./live"
import { choose, how, open, own, type Place, type Reveal, symbols } from "./place"
import { sideBySide } from "./split"

type Mode = "rich" | "source"
/** The mode, the lock, and Source's page shown or folded. */
type Look = { mode: Mode; locked: boolean; preview: boolean }
const mode = (value: unknown): Mode | undefined => (value === "rich" || value === "source" ? value : undefined)
/** The card's look, the last its Markdown pages showed: a page shown anew or again shows it. */
let cardLook: Look | undefined
/** A card's mode from before the lock: Read and Live Edit are Rich Text, locked and not; Side by Side is Source with
 *  its page shown (Source is Source, folded). */
const OLD: Record<string, Partial<Look>> = {
  read: { mode: "rich", locked: true },
  live: { mode: "rich", locked: false },
  split: { mode: "source", preview: true },
}

/** GitHub's anchor of a heading's text, for `#` links. */
const slug = (text: string) => text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s/g, "-")

/** Locked: no text box for VoiceOver, an article; a drop changes nothing. Not read only: the editor's read only is
 *  the file's (`editor`), and a tick while locked writes. */
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
/** Rich Text's look, and Source's page: prose in the system font at the mockup's 14 pt (the app's
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

/** A locked view's selection as source text: the page's selection mapped onto the document (an end outside the editor is the
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
  // The card's look: as another Markdown page left it, else as the card's own choices (a relaunch), else the settings.
  const choices = own(ovvi), old = OLD[choices.mode ?? ""]
  const kept = { ...old, ...choices, mode: old?.mode ?? choices.mode }
  const first: Look = cardLook ?? {
    mode: mode(kept.mode) ?? mode(ovvi.settings.get("markdown")) ?? "rich",
    locked: kept.locked ?? ovvi.settings.get<boolean>("markdown-lock") !== false,
    preview: kept.preview ?? false,
  }
  /** As drawn: the editor starts as Rich Text, locked. */
  let now: Look = { mode: "rich", locked: true, preview: false }
  let outlined = false
  /** The file has a heading: the outline's toggle shows only then. */
  let titled = false
  const editable = new Compartment(), look = new Compartment()
  /** Source's page, while Source shows. */
  let split: ReturnType<typeof sideBySide> | undefined
  keep(() => split?.destroy())

  /** Shows the look and the outline or not, and sets row 2 and Lock Editing to match. */
  function present(view: EditorView, next: Look, nowOutlined: boolean) {
    const effects = []
    if (next.locked !== now.locked) {
      // Locked keeps no selection drawn, nor a search panel opened with Replace's row.
      if (next.locked) closeSearchPanel(view)
      effects.push(editable.reconfigure(markdownMode(!next.locked)))
    }
    if (next.mode !== now.mode) {
      effects.push(look.reconfigure(next.mode === "source" ? source : rendered))
      // A new look keeps the line at the top in place.
      const top = view.lineBlockAtHeight(view.scrollDOM.scrollTop - view.documentPadding.top).from
      effects.push(EditorView.scrollIntoView(top, { y: "start" }))
    }
    const selection = next.locked ? { anchor: view.state.selection.main.head } : undefined
    if (effects.length) view.dispatch({ selection, effects })
    if (next.mode !== now.mode || (split && next.preview !== now.preview)) {
      split?.destroy()
      split = next.mode === "source" ? sideBySide(view, pane, page, next.preview, folded) : undefined
    }
    now = cardLook = next
    outlined = nowOutlined && titled
    outline.hidden = false
    outline.toggleAttribute("data-closed", !outlined)
    if (outlined) list(view, all(view.state))
    focus(view)
    ovvi.controls.set("mode", { value: next.mode })
    // Lit while the page edits; its help says what a click does.
    ovvi.controls.set("lock", {
      value: !next.locked, symbol: next.locked ? "lock.fill" : "lock.open", title: next.locked ? "Unlock" : "Lock",
    })
    ovvi.controls.set("outline", { value: outlined })
    ovvi.controls.set("lock-editing", { enabled: true, checked: next.locked })
  }

  /** The user folded Source's page or showed it: the card keeps it. */
  function folded(preview: boolean) {
    now = cardLook = { ...now, preview }
    choose(ovvi, { preview })
  }

  /** The look's change the user made in row 2 or with ⌘E: the card keeps it. */
  function change(view: EditorView, to: Partial<Look>) {
    choose(ovvi, to)
    present(view, { ...now, ...to }, outlined)
  }

  /** Unlocked, the editor takes the keyboard; locked, the page, so the keys scroll it. */
  function focus(view: EditorView) {
    if (!now.locked) view.focus()
    else view.scrollDOM.focus({ preventScroll: true })
  }

  /** The outline's toggle shows while the file has headings; with none, the outline closes. */
  function titles(view: EditorView, found: ReturnType<typeof headings>) {
    if (found.length > 0 !== titled) {
      titled = found.length > 0
      ovvi.controls.set("outline", { hidden: !titled })
      if (!titled && outlined) present(view, now, false)
    }
    if (outlined) list(view, found)
  }

  /** The outline's rows; a click scrolls to its heading, and unlocked puts the caret there. */
  function list(view: EditorView, found: ReturnType<typeof headings>) {
    outline.replaceChildren(...found.map((heading) => {
      const row = document.createElement("button")
      row.textContent = heading.text
      row.style.paddingLeft = `${12 * heading.level}px`
      row.onclick = () => {
        const effects = EditorView.scrollIntoView(heading.from, { y: "start" })
        view.dispatch(!now.locked ? { selection: { anchor: heading.from }, effects } : { effects })
        focus(view)
      }
      return row
    }))
  }

  /** Links while locked: `#` scrolls to its heading, http(s) opens a browser pane in a new tab (⌥ to the side), a
   *  relative path its file in the card (⌘ in a new tab, ⌥ to the side). */
  function follow(view: EditorView, event: MouseEvent) {
    const link = (event.target as Element).closest("a")
    if (!link) return false
    // Unlocked too: a table's `href=""` link would load the page again and lose the edits.
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
  ovvi.controls.set("mode", { value: first.mode })
  ovvi.controls.set("outline", { value: false })
  ovvi.controls.set("lock-editing", { enabled: true, checked: first.locked })
  symbols(ovvi, ["chevron.left", "chevron.right"])
  let shown: Editor
  /** The saves of ticks made while locked, one after the other: a save under way skips a second one. */
  let ticks = Promise.resolve()
  // Front matter as YAML, not as a rule and a heading.
  const language = yamlFrontmatter({ content: markdown({ base: markdownLanguage }) })
  const links = EditorView.domEventHandlers({ click: (event, view) => follow(view, event) })
  /** Source: the file as code cards draw it. */
  const source = [code, Prec.highest(EditorView.theme({ ".cm-content": { paddingBottom: "48px" } }))]
  /** Source's page: Rich Text's look, locked, with its links and its ticks. */
  const page = [language, rendered, selected, markdownMode(false), EditorView.lineWrapping, links]
  shown = await editor(place, [
    language,
    look.of(rendered),
    editable.of(markdownMode(false)),
    EditorView.lineWrapping,
    links,
    EditorView.updateListener.of((update) => {
      split?.follow(update)
      // A box ticked while locked is saved at once, as the card's ⌘S, after any save under way; unlocked it waits for
      // ⌘S as any edit.
      if (now.locked && update.transactions.some((tr) => tr.annotation(ticked))) {
        ticks = ticks.then(() => shown?.save())
      }
      // Also as the background parse reaches more headings.
      if (update.docChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        const found = headings(update.state)
        // No heading in a tree cut short says nothing: its headings can be below the parsed part.
        if (found.length || syntaxTreeAvailable(update.state)) titles(update.view, found)
      }
    }),
  ], pane)

  // None when the file is too large to show: the info view is there instead, and Lock Editing does nothing.
  if (!shown) {
    ovvi.controls.set("lock-editing", { enabled: false })
    ovvi.controls.set("mode", { hidden: true })
    ovvi.controls.set("lock", { hidden: true })
    return undefined
  }
  const { view, land } = shown
  // Copy while locked, when the keyboard is on the scroller: the source of the selection, also of lines not drawn
  // (Select All's selection reaches past the editor). Not from the find field or Source's page.
  const copy = (event: ClipboardEvent) => {
    const mine = view.scrollDOM.contains(document.activeElement)
    const text = !now.locked || !mine || event.defaultPrevented || !place.shown() ? undefined : copied(view)
    if (text === undefined) return
    event.clipboardData?.setData("text/plain", text)
    event.preventDefault()
  }
  document.addEventListener("copy", copy)
  keep(() => document.removeEventListener("copy", copy))
  ovvi.on("control", ({ id, value }) => {
    if (id === "outline") present(view, now, value === true)
    if (id === "mode" && mode(value)) change(view, { mode: mode(value) })
    if (id === "lock") change(view, { locked: value !== true })
    if (id === "lock-editing") change(view, { locked: !now.locked })
  })
  // A new setting, while the card has no choice of its own (an old mode is one).
  ovvi.on("settings", (changed) => {
    const next = mode(changed.markdown), locked = changed["markdown-lock"]
    if (next && kept.mode === undefined) present(view, { ...now, mode: next }, outlined)
    if (typeof locked === "boolean" && kept.locked === undefined) present(view, { ...now, locked }, outlined)
  })
  titles(view, all(view.state))
  // A linked open at a line (a diff's) puts the caret there (`editor`), unlocked or not. Back's landing is a path.
  present(view, first, false)
  // A kept page shown again (Back, Forward, a link) takes the card's look.
  ovvi.on("place", () => cardLook && present(view, cardLook, outlined))
  // The app gives the card the keyboard: after the editor's own handler, a locked page takes it.
  const take = () => place.shown() && focus(view)
  addEventListener("focus", take)
  keep(() => removeEventListener("focus", take))
  return land
}
