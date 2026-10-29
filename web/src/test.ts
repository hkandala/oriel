// The web host's test page: the card's file in CodeMirror, reporting dirty. Phase 44's kinds replace it.
import { basicSetup, EditorView } from "codemirror"
import { arg, ask, report } from "./lib/bridge"

const { text } = await ask({ op: "read", path: arg })
let dirty = false
new EditorView({
  doc: text,
  parent: document.body,
  extensions: [
    basicSetup,
    EditorView.theme({
      "&": { height: "100%", fontSize: "var(--font-size)" },
      ".cm-scroller": { fontFamily: "ui-monospace, monospace" },
      ".cm-content": { caretColor: "var(--text)" },
      ".cm-gutters": { background: "transparent", color: "var(--dim)", border: "none" },
      ".cm-activeLine, .cm-activeLineGutter": { background: "color-mix(in srgb, var(--text) 6%, transparent)" },
      "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
        background: "color-mix(in srgb, var(--accent) 35%, transparent)",
      },
    }),
    EditorView.updateListener.of((update) => {
      const now = update.state.doc.toString() !== text
      if (now !== dirty) {
        dirty = now
        report({ op: "dirty", dirty })
      }
    }),
  ],
})
