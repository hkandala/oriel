// The CodeMirror editor of a card's file, shared by File and Markdown: the file read over the bridge, its dirty
// report, ⌘S and ⌘F from the app's menu, and a reload from disk.
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
import { ask, at, type FileReply, type In, receive, report } from "./bridge"
import { failed, info } from "./info"

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

/** The text on disk as last read or saved, and the one a save in flight sent. */
let disk: Text
let saving: Text | undefined
let dirty = false

const update = (state: EditorState) => {
  const now = !state.doc.eq(disk)
  if (now !== dirty) {
    dirty = now
    report({ op: "dirty", dirty })
  }
}

/** The file's text from disk: only the changed middle is replaced, so the caret and the scroll stay. */
const load = (view: EditorView, text: string) => {
  // Positions count a line break as one character, whatever the file's.
  const next = view.state.toText(text), old = view.state.doc.toString(), now = next.toString()
  let from = 0
  while (from < old.length && from < now.length && old[from] === now[from]) from++
  let end = 0
  while (end < old.length - from && end < now.length - from && old.at(-1 - end) === now.at(-1 - end)) end++
  const reload = view.state.update({ changes: { from, to: old.length - end, insert: next.slice(from, now.length - end) } })
  // Before the update, which reports dirty against it.
  disk = reload.state.doc
  view.dispatch(reload)
}

/** Only edits: a save of the text on disk would still wake every watcher of the file. */
export const save = (view: EditorView) => {
  if (view.state.readOnly || !dirty) return
  saving = view.state.doc
  report({ op: "save", text: view.state.sliceDoc() })
}

export const find = (view: EditorView) => openSearchPanel(view)

/** The app's messages for the editor; a page that hears more calls it for the rest. */
export const handle = (view: EditorView, message: In) => {
  switch (message.op) {
    case "load":
      // A file now too large, or now read only (not UTF-8, over a remote cap): the page starts again with it.
      if ("text" in message && message.readOnly === view.state.readOnly) load(view, message.text)
      else location.reload()
      break
    case "saved":
      disk = saving ?? disk
      update(view.state)
      break
    case "save":
      save(view)
      break
    case "find":
      find(view)
      break
    case "findNext":
      findNext(view)
      break
    case "findPrevious":
      findPrevious(view)
  }
}

/** The card's file in an editor under `parent`, or the info view when the file is too large to show. */
export async function editor(extensions: Extension[], parent = document.body) {
  const file: FileReply | undefined = await ask({ op: "read" }).catch((error) => failed(error, parent))
  if (!file) return undefined
  if ("info" in file) {
    info(file.info, parent)
    return undefined
  }
  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: file.text,
      extensions: [
        // A CRLF file saves as CRLF.
        file.text.includes("\r\n") ? EditorState.lineSeparator.of("\r\n") : [],
        EditorState.readOnly.of(file.readOnly),
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
  const line = Number(at)
  if (line >= 1 && line <= view.state.doc.lines) {
    const pos = view.state.doc.line(line).from
    view.dispatch({ selection: { anchor: pos }, effects: EditorView.scrollIntoView(pos, { y: "center" }) })
  }
  receive((message) => handle(view, message))
  // The app gives the card's web view the keyboard: the editor takes it.
  addEventListener("focus", () => view.focus())
  if (document.hasFocus()) view.focus()
  return view
}
