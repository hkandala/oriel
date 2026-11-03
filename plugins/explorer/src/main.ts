// File Explorer: one card that moves between four places, each its own module loaded on first use: the tree of a
// folder (files.ts), and a file as text (file.ts), as Markdown (markdown.ts) or as an image, a PDF or a player
// (preview.ts). The app draws row 2 from the manifest; each place shows its own controls. The card keeps the pages
// it showed (`oriel.pages`).
import type { Oriel } from "@oriel/plugin-api"
import "./explorer.css"
import "./files.css"
import "./markdown.css"
import "./preview.css"
import { kind, type Place, type Reveal } from "./place"

type Kind = ReturnType<typeof kind>

/** Each place's controls in row 2; the rest hide. Preview shows its page and zoom itself. */
const CONTROLS: Record<Kind, string[]> = {
  files: ["root", "filter", "collapse", "hidden-files"],
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
  /** The trees the card showed, last last: Show in File Explorer goes back to the one a file came from. */
  const trees: string[] = []

  // Show in File Explorer: the tree the file came from, else its repository's root, else its folder.
  oriel.on("control", async ({ id }) => {
    if (id !== "reveal") return
    const file = oriel.card.arg, folder = file.slice(0, file.lastIndexOf("/")) || "/"
    let root = trees.findLast((tree) => file.startsWith(tree))
    root ??= (await oriel.git.root(folder).catch(() => null)) ?? folder
    if (oriel.card.arg === file) oriel.card.go(root.endsWith("/") ? root : `${root}/`, { at: file })
  })
  // Each place in a page of its own, which the card keeps: Back and Forward show it as it was.
  await oriel.pages.route(async (page) => {
    const { arg, element: root } = page, place = kind(arg), scoped = page.oriel
    // Once each, last last.
    if (place === "files") trees.splice(0, trees.length, ...trees.filter((tree) => tree !== arg), arg)
    // A new tree starts with no filter; a kept one keeps its own.
    for (const id of ALL) {
      const hidden = !CONTROLS[place].includes(id)
      scoped.controls.set(id, id === "filter" ? { hidden, value: "" } : { hidden })
    }
    scoped.controls.set("open-with", { value: place === "files" ? "" : arg })
    if (place !== "markdown") scoped.controls.set("edit-mode", { enabled: false, checked: false })
    root.dataset.place = place
    // A text file's read starts while its place's code loads.
    const read = place === "file" || place === "markdown" ? oriel.files.read(arg) : undefined
    read?.catch(() => undefined)
    const reveal = await (await load(place)).show({
      oriel: scoped, arg, at: page.at, root, read,
      keep: page.keep,
      again: page.redraw,
      live: () => !page.dropped,
      shown: () => page.shown,
    })
    // The card back at this page with a landing: Back from a file it opened, Show in File Explorer.
    if (reveal) scoped.on("place", ({ at }) => at && reveal(at))
  })
}
