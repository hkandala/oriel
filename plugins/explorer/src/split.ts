// Markdown's Side by Side (markdown.ts): the rendered page beside the source, a second CodeMirror view of the same
// text. The source's changes go to the page, and a tick in the page goes to the source as an edit. The two scroll
// together by source line: the one the user last scrolled, clicked or typed in leads. A button on the divider folds
// the page away and back.
import { Annotation, EditorState, type Extension } from "@codemirror/state"
import { EditorView, type ViewUpdate } from "@codemirror/view"

/** A change one view passed to the other: it goes no further. */
const synced = Annotation.define<boolean>()

/** `to` scrolled so the source line at the top of `from` is at its top, as far into the line. */
function align(from: EditorView, to: EditorView) {
  const at = from.scrollDOM.scrollTop - from.documentPadding.top, block = from.lineBlockAtHeight(at)
  const line = to.lineBlockAt(block.from), into = (at - block.top) / Math.max(block.height, 1)
  to.scrollDOM.scrollTop = line.top + to.documentPadding.top + into * line.height
}

/** The page beside `source` in `parent`, drawn with `extensions`; `follow` passes on the source's changes. */
export function sideBySide(source: EditorView, parent: HTMLElement, extensions: Extension) {
  const divider = Object.assign(document.createElement("div"), { className: "split-divider" })
  const fold = Object.assign(document.createElement("button"), { type: "button", className: "split-fold" })
  const folded = (yes: boolean) => {
    parent.toggleAttribute("data-folded", yes)
    fold.title = fold.ariaLabel = yes ? "Show Preview" : "Hide Preview"
  }
  folded(false)
  fold.onclick = () => {
    folded(!parent.hasAttribute("data-folded"))
    if (!parent.hasAttribute("data-folded")) align(source, page)
  }
  divider.append(fold)
  parent.append(divider)
  const page: EditorView = new EditorView({
    parent,
    state: EditorState.create({
      doc: source.state.doc,
      // First: the first read only value wins, and the page's Read look says read only.
      extensions: [EditorState.readOnly.of(source.state.readOnly), extensions],
    }),
    dispatchTransactions(transactions, view) {
      view.update(transactions)
      for (const tr of transactions) {
        if (tr.docChanged && !tr.annotation(synced)) source.dispatch({ changes: tr.changes, annotations: synced.of(true) })
      }
    },
  })
  // The page leads after the user's input in it; anything else (the source, the outline, find) gives it back. Not by
  // hover: the source scrolls by keys under a pointer resting on the page. And the page's own height changes (its
  // widgets measured) never move the source.
  let pageLeads = false
  const input = (event: Event) => {
    const target = event.type === "keydown" ? document.activeElement : event.target
    pageLeads = target instanceof Node && page.dom.contains(target)
  }
  for (const type of ["wheel", "pointerdown", "keydown"]) addEventListener(type, input, { capture: true, passive: true })
  const leads = () => !pageLeads && !parent.hasAttribute("data-folded") && align(source, page)
  const follows = () => pageLeads && align(page, source)
  source.scrollDOM.addEventListener("scroll", leads)
  page.scrollDOM.addEventListener("scroll", follows)
  // After the page's first layout.
  page.requestMeasure({ read: () => undefined, write: () => align(source, page) })
  return {
    follow(update: ViewUpdate) {
      for (const tr of update.transactions) {
        if (tr.docChanged && !tr.annotation(synced)) page.dispatch({ changes: tr.changes, annotations: synced.of(true) })
      }
    },
    destroy() {
      for (const type of ["wheel", "pointerdown", "keydown"]) removeEventListener(type, input, { capture: true })
      source.scrollDOM.removeEventListener("scroll", leads)
      page.destroy()
      divider.remove()
      parent.removeAttribute("data-folded")
    },
  }
}
