// File Explorer: one card that moves between four places, each its own module loaded on first use: the tree of a
// folder (files.ts), and a file as text (file.ts), as Markdown (markdown.ts) or as an image, a PDF or a player
// (preview.ts). The app draws row 2 from the manifest; each place shows its own controls. The card keeps the pages
// it showed (`ovvi.pages`).
import type { Ovvi } from "@ovvi/plugin-api"
import "./explorer.css"
import "./files.css"
import "./find.css"
import "./markdown.css"
import "./preview.css"
import { kind, type Place, type Reveal, trail } from "./place"

type Kind = ReturnType<typeof kind>

/** Each place's controls in row 2; the rest hide. A file's row is one row for every kind: its breadcrumbs at the
 *  left, Show in File Explorer and Open With at the right. Preview shows its page and zoom itself, Markdown its
 *  outline's toggle. */
const CONTROLS: Record<Kind, string[]> = {
  files: ["root", "filter", "collapse", "hidden-files"],
  file: ["jump", "spacer", "wrap", "reveal", "open-with"],
  preview: ["jump", "spacer", "reveal", "open-with"],
  markdown: ["jump", "spacer", "reveal", "mode", "open-with"],
}
const ALL = [
  ...new Set([...Object.values(CONTROLS).flat(), "outline", "page", "zoom.fit", "zoom.actual", "zoom.out", "zoom.in"]),
]

const load = (kind: Kind): Promise<{ show(place: Place): Promise<Reveal> }> =>
  kind === "files" ? import("./files")
    : kind === "file" ? import("./file")
    : kind === "markdown" ? import("./markdown")
    : import("./preview")

export default async function main(ovvi: Ovvi) {
  // Show in File Explorer: the tree of the file's folder, the file selected.
  ovvi.on("control", ({ id }) => {
    if (id !== "reveal") return
    const file = ovvi.card.arg
    ovvi.card.go(file.slice(0, file.lastIndexOf("/") + 1), { at: file })
  })
  // Each place in a page of its own, which the card keeps: Back and Forward show it as it was.
  await ovvi.pages.route(async (page) => {
    const { arg, element: root } = page, place = kind(arg), scoped = page.ovvi
    // A new tree starts with no filter; a kept one keeps its own.
    for (const id of ALL) {
      const hidden = !CONTROLS[place].includes(id)
      scoped.controls.set(id, id === "filter" ? { hidden, value: false } : { hidden })
    }
    scoped.controls.set("open-with", { value: place === "files" ? "" : arg })
    if (place !== "markdown") scoped.controls.set("edit-mode", { enabled: false, checked: false })
    root.dataset.place = place
    // A text file's read starts while its place's code loads.
    const read = place === "file" || place === "markdown" ? ovvi.files.read(arg) : undefined
    read?.catch(() => undefined)
    const [code, crumbs] = await Promise.all([load(place), place === "files" ? [] : trail(scoped, arg)])
    if (place !== "files") scoped.controls.set("jump", { value: crumbs, symbol: "" })
    const reveal = await code.show({
      ovvi: scoped, arg, at: page.at, root, read, trail: crumbs,
      keep: page.keep,
      again: page.redraw,
      live: () => !page.dropped,
      shown: () => page.shown,
    })
    // The card back at this page with a landing: Back from a file it opened, Show in File Explorer.
    if (reveal) scoped.on("place", ({ at }) => at && reveal(at))
  })
}
