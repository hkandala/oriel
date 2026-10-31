// File Explorer: one card that moves between four places, each its own module loaded on first use: the tree of a
// folder (files.ts), and a file as text (file.ts), as Markdown (markdown.ts) or as an image, a PDF or a player
// (preview.ts). The app draws row 2 from the manifest; each place shows its own controls.
import "pdfjs-dist/web/pdf_viewer.css"
import type { Off, Oriel } from "@oriel/plugin-api"
import "./explorer.css"
import "./files.css"
import "./markdown.css"
import "./preview.css"
import type { Place, Reveal } from "./place"
import { previews } from "./preview"

type Kind = "files" | "file" | "preview" | "markdown"
/** The place shown: its argument, its root, what ends with it, and its landing for the same place again. */
type Shown = { arg: string; root: HTMLElement; offs: Off[]; reveal: Reveal }

/** Known kinds that are not text: Preview's info view, not File's. ponytail: by extension, as the app has no file
 *  types for a page; File shows the info view too for any other file that is not UTF-8 text. */
const BINARY = new Set(("zip gz tgz tar bz2 xz 7z rar zst dmg pkg iso img bin exe dll so dylib a o class jar war apk ipa "
  + "wasm pyc sqlite db doc docx xls xlsx ppt pptx pages numbers key odt ods odp psd ai eps ico icns avif raw dng ttf "
  + "otf woff woff2").split(" "))

/** Which place shows the argument, by its name alone (a remote file is not read first). */
function kind(arg: string): Kind {
  if (arg.endsWith("/")) return "files"
  const ext = (/\.([^./]+)$/.exec(arg)?.[1] ?? "").toLowerCase()
  if (["md", "markdown", "mdx"].includes(ext)) return "markdown"
  // `.ts` is TypeScript, not an MPEG-2 stream; a repository's `.plist` is XML.
  if (!ext || ["ts", "mts", "cts", "plist"].includes(ext)) return "file"
  return previews(arg) || BINARY.has(ext) ? "preview" : "file"
}

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
   *  same place again only lands, unless `fresh`. */
  const show = (arg: string, at?: string, fresh = false) =>
    (turn = turn.then(async () => {
      if (shown?.arg === arg && !fresh) {
        if (at) shown.reveal?.(at)
        return
      }
      const place = kind(arg), old = shown
      old?.offs.splice(0).forEach((off) => off())
      if (place === "files") trees.push(arg)
      for (const id of ALL) oriel.controls.set(id, { hidden: !CONTROLS[place].includes(id) })
      oriel.controls.set("open-with", { value: place === "files" ? "" : arg })
      if (place !== "markdown") oriel.controls.set("edit-mode", { enabled: false, checked: false })
      const root = Object.assign(document.createElement("div"), { className: "place" })
      root.dataset.place = place
      root.style.visibility = "hidden"
      document.body.append(root)
      const offs: Off[] = []
      const now: Shown = (shown = { arg, root, offs, reveal: undefined })
      const keep = (off: Off) => void offs.push(off)
      try {
        const again = () => shown === now && void show(arg, undefined, true)
        now.reveal = await (await load(place)).show({ oriel, arg, at, root, keep, again })
      } catch (error) {
        console.error(error)
      }
      old?.root.remove()
      root.style.visibility = ""
      // A place takes the keyboard on the window's focus, which it had: the editor, Read's page.
      if (document.hasFocus()) dispatchEvent(new Event("focus"))
    }))

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
