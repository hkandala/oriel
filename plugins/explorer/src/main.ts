// File Explorer: one card that moves between four places, each its own module loaded on first use: the tree of a
// folder (files.ts), and a file as text (file.ts), as Markdown (markdown.ts) or as an image, a PDF or a player
// (preview.ts). The app draws row 2 from the manifest; each place shows its own controls.
import type { Off, Oriel } from "@oriel/plugin-api"
import "./explorer.css"
import "./files.css"
import "./markdown.css"
import "./preview.css"
import { kind, type Place, type Reveal } from "./place"

type Kind = ReturnType<typeof kind>
/** The place shown: its argument, its root, what ends with it, and its landing for the same place again. */
type Shown = { arg: string; root: HTMLElement; offs: Off[]; reveal: Reveal }

/** Each place's controls in row 2; the rest hide. Preview shows its page and zoom itself. */
const CONTROLS: Record<Kind, string[]> = {
  files: ["root", "filter", "collapse"],
  file: ["jump", "spacer", "reveal", "open-with"],
  preview: ["path", "spacer", "reveal", "open-with"],
  markdown: ["mode", "outline", "spacer", "reveal", "open-with"],
}
const ALL = [...new Set([...Object.values(CONTROLS).flat(), "page", "zoom.fit", "zoom.actual", "zoom.out", "zoom.in"])]

const load = (kind: Kind): Promise<{ show(place: Place): Promise<Reveal> }> =>
  kind === "files" ? import("./files")
    : kind === "file" ? import("./file")
    : kind === "markdown" ? import("./markdown")
    : import("./preview")

export default async function main(oriel: Oriel) {
  let shown: Shown | undefined
  /** The trees the card showed, last last: Show in File Explorer goes back to the one a file came from. */
  const trees: string[] = []
  /** One move at a time, in order. */
  let turn = Promise.resolve()

  /** The place drawn in a root of its own, hidden until it drew (or failed), so the old one shows until then. The
   *  same place again only lands, unless `fresh`. A place the card already left is not drawn. */
  const show = (arg: string, at?: string, fresh = false) => {
    const work = async () => {
      if (!fresh && arg !== oriel.card.arg) return
      if (shown?.arg === arg && !fresh) {
        if (at) shown.reveal?.(at)
        return
      }
      const place = kind(arg), old = shown
      if (place === "files") trees.push(arg)
      // The filter shows empty: a field shown with text takes the keyboard (FilterField), and the tree starts with
      // none. In the same change, so it never shows with the last tree's text, nor a saved one.
      for (const id of ALL) {
        const hidden = !CONTROLS[place].includes(id)
        oriel.controls.set(id, id === "filter" ? { hidden, value: "" } : { hidden })
      }
      oriel.controls.set("open-with", { value: place === "files" ? "" : arg })
      if (place !== "markdown") oriel.controls.set("edit-mode", { enabled: false, checked: false })
      const root = Object.assign(document.createElement("div"), { className: "place" })
      root.dataset.place = place
      root.style.visibility = "hidden"
      document.body.append(root)
      const offs: Off[] = []
      const now: Shown = (shown = { arg, root, offs, reveal: undefined })
      const keep = (off: Off) => void offs.push(off)
      const live = () => shown === now
      const again = () => live() && void show(arg, undefined, true)
      try {
        now.reveal = await (await load(place)).show({ oriel, arg, at, root, keep, again, live })
      } catch (error) {
        console.error(error)
      }
      // The old place's views go only now: CodeMirror and the tree take their DOM with them.
      old?.offs.splice(0).forEach((off) => off())
      old?.root.remove()
      root.style.visibility = ""
      // A place takes the keyboard on the window's focus, which it had: the editor, Read's page.
      if (document.hasFocus()) dispatchEvent(new Event("focus"))
    }
    // A move that failed leaves the next one free to run.
    return (turn = turn.then(work, work).catch((error) => console.error(error)))
  }

  oriel.on("place", ({ arg, at }) => void show(arg, at))
  // Show in File Explorer: the tree the file came from, else its repository's root, else its folder.
  oriel.on("control", async ({ id }) => {
    if (id !== "reveal") return
    const file = oriel.card.arg, folder = file.slice(0, file.lastIndexOf("/")) || "/"
    let root = trees.findLast((tree) => file.startsWith(tree))
    root ??= (await oriel.git.root(folder).catch(() => null)) ?? folder
    if (oriel.card.arg === file) oriel.card.go(root.endsWith("/") ? root : `${root}/`, { at: file })
  })
  await show(oriel.card.arg, oriel.card.at)
}
