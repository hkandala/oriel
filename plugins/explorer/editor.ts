// The CodeMirror editor of a card's file, shared by File and Markdown: the file read through the app, the Edited dot,
// ⌘S saved by the hash it was read with, ⌘F from the app's menu, and the file again after a change on disk.
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import { bracketMatching, indentOnInput } from "@codemirror/language"
import {
  findNext,
  findPrevious,
  highlightSelectionMatches,
  openSearchPanel,
  search,
  searchKeymap,
} from "@codemirror/search"
import { EditorState, type Extension, type Text } from "@codemirror/state"
import { drawSelection, EditorView, highlightActiveLine, highlightSpecialChars, keymap } from "@codemirror/view"
import type { OrielError } from "@oriel/plugin-api"
import { failed, info } from "./info"
import { name, type Place } from "./place"

const theme = EditorView.theme({
  "&": { height: "100%", fontSize: "var(--font-size)" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: "ui-monospace, monospace", lineHeight: "1.5" },
  ".cm-content": { caretColor: "var(--text)" },
  ".cm-gutters": { background: "transparent", color: "var(--dim)", border: "none" },
  ".cm-activeLine, .cm-activeLineGutter": { background: "color-mix(in srgb, var(--text) 6%, transparent)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    background: "color-mix(in srgb, var(--accent) 35%, transparent)",
  },
  ".cm-searchMatch": { background: "color-mix(in srgb, var(--finished) 35%, transparent)" },
  ".cm-panels": { background: "transparent", color: "var(--text)" },
  ".cm-panels-top": { borderBottom: "1px solid var(--divider)" },
})

/** The editor and the caret's landing; undefined when the info view shows instead. */
export type Editor = { view: EditorView; land(at: string | undefined): void } | undefined

/** The place's file in an editor under `parent`, or the info view when it is not text or too large to show. A file
 *  that becomes read only, writable, too large or not text shows the place anew (`again`). */
export async function editor(place: Place, extensions: Extension[], parent: HTMLElement): Promise<Editor> {
  const { oriel, arg: path, keep, again } = place
  const file = await oriel.files.read(path).catch((error: OrielError) => error)
  if (file instanceof Error) {
    if (file.code === "notText" || file.code === "tooLarge") await info(oriel, path, parent)
    else failed(file, parent)
    return undefined
  }
  /** The text on disk as last read or saved, its hash, and the text a save in flight sent. */
  let disk: Text
  let hash = file.hash
  let saving: Text | undefined
  let dirty = false

  const update = (state: EditorState) => {
    const now = !state.doc.eq(disk)
    if (now !== dirty) {
      dirty = now
      oriel.card.setDirty(dirty)
    }
  }

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: file.text,
      extensions: [
        // A CRLF file saves as CRLF.
        file.text.includes("\r\n") ? EditorState.lineSeparator.of("\r\n") : [],
        EditorState.readOnly.of(!file.writable),
        highlightSpecialChars(),
        history(),
        drawSelection(),
        indentOnInput(),
        bracketMatching(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        search({ top: true }),
        keymap.of([...defaultKeymap, ...searchKeymap, ...historyKeymap, indentWithTab]),
        theme,
        EditorView.updateListener.of((u) => u.docChanged && update(u.state)),
        extensions,
      ],
    }),
  })
  disk = view.state.doc
  keep(() => {
    view.destroy()
    if (dirty) oriel.card.setDirty(false)
  })

  /** The file's text from disk: only the changed middle is replaced, so the caret and the scroll stay. */
  const load = (text: string, now: string) => {
    hash = now
    // Positions count a line break as one character, whatever the file's.
    const next = view.state.toText(text), old = view.state.doc.toString(), shown = next.toString()
    let from = 0
    while (from < old.length && from < shown.length && old[from] === shown[from]) from++
    let end = 0
    while (end < old.length - from && end < shown.length - from && old.at(-1 - end) === shown.at(-1 - end)) end++
    const reload = view.state.update({
      changes: { from, to: old.length - end, insert: next.slice(from, shown.length - end) },
    })
    // Before the update, which reports dirty against it.
    disk = reload.state.doc
    view.dispatch(reload)
  }

  /** The file again; a file now too large, not text or read only shows the place anew. */
  const reload = async () => {
    const now = await oriel.files.read(path).catch(() => undefined)
    if (now?.writable !== !view.state.readOnly) return again()
    load(now.text, now.hash)
  }

  /** Only edits: a save of the text on disk would still wake every watcher of the file. One at a time: a second
   *  would check the first's old hash; its edits keep the dot for the next ⌘S. `over` undefined overwrites. */
  const save = async (over: string | undefined = hash) => {
    if (view.state.readOnly || !dirty || saving) return
    const sent = (saving = view.state.doc)
    let failure: OrielError | undefined
    try {
      // In the file's own line breaks.
      hash = (await oriel.files.write(path, view.state.sliceDoc(), { over })).hash
      disk = sent
      update(view.state)
    } catch (error) {
      failure = error as OrielError
    } finally {
      saving = undefined
    }
    if (failure?.code === "changed") {
      const picked = await oriel.toast(`${name(path)} changed on disk since you opened it.`, ["Overwrite", "Reload"])
      if (picked === "Overwrite") await save(undefined)
      if (picked === "Reload") await reload()
    } else if (failure) {
      const text = `${name(path)} was not saved: ${failure.message}`
      if ((await oriel.toast(text, ["Cancel", "Try Again"])) === "Try Again") await save(over)
    }
  }

  /** After a change on disk: a clean file reloads; a dirty one asks. Not for the card's own save, nor before the file
   *  changed (the card shown again). */
  const check = async () => {
    const before = hash
    const now = await oriel.files.read(path).catch(() => undefined)
    if (!now || now.hash === before || saving || hash !== before) return
    if (now.writable === view.state.readOnly) return again()
    if (!dirty) return load(now.text, now.hash)
    const picked = await oriel.toast(`${name(path)} changed on disk.`, ["Reload", "Keep Mine"])
    if (picked === "Reload") void reload()
    // The next ⌘S writes over the disk's new version.
    if (picked === "Keep Mine") hash = now.hash
  }

  /** The caret on a 1-based line, in the middle of the card. */
  const land = (at: string | undefined) => {
    const line = Number(at)
    if (!(line >= 1 && line <= view.state.doc.lines)) return
    const pos = view.state.doc.line(line).from
    view.dispatch({ selection: { anchor: pos }, effects: EditorView.scrollIntoView(pos, { y: "center" }) })
  }
  land(place.at)

  keep(oriel.on("save", () => void save()))
  keep(oriel.on("find", () => openSearchPanel(view)))
  keep(oriel.on("findNext", () => findNext(view)))
  keep(oriel.on("findPrevious", () => findPrevious(view)))
  keep(oriel.files.watch(path, () => void check()))
  // The app gives the card's web view the keyboard: the editor takes it.
  const focus = () => view.focus()
  addEventListener("focus", focus)
  keep(() => removeEventListener("focus", focus))
  if (document.hasFocus()) view.focus()
  return { view, land }
}
