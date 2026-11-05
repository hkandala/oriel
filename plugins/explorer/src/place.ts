// What every place of the card gets from `main.ts`, and the open gestures they share.
import type { Off, Oriel } from "@oriel/plugin-api"
import places from "../places.json"

export type Place = {
  /** The page's own: its handlers, watches and header controls wait while it is hidden (`oriel.pages`). */
  oriel: Oriel
  /** The place's argument: a folder's path with its `/`, or a file's path. */
  arg: string
  /** A linked open's landing: a line, or the path to reveal in the tree. */
  at?: string
  /** The page: the place draws in here; it shows once `show` returned. */
  root: HTMLElement
  /** Ends with the place: a view's teardown. `oriel`'s handlers and watches end with it on their own. */
  keep(off: Off): void
  /** Shows the place anew, as it first showed: its file became read only or too large. */
  again(): void
  /** The card keeps the page: work that ends after it dropped does nothing. */
  live(): boolean
  /** The page shows: a hidden one leaves the keyboard and the clipboard alone. */
  shown(): boolean
  /** File's and Markdown's file, read already. */
  read?: ReturnType<Oriel["files"]["read"]>
  /** A file's breadcrumbs (`trail`); none for a folder. */
  trail: string[]
}

/** A file's extension, lowercased; "" for none, also for a dotfile's name (as `NSString.pathExtension`). */
export const extension = (path: string) => (/[^/]\.([^./]+)$/.exec(path)?.[1] ?? "").toLowerCase()

/** What Preview draws of a file, by its extension: the kinds in places.json, "" for the info view. */
export const drawn = (path: string) => {
  const ext = extension(path)
  return (["image", "pdf", "audio", "video"] as const).find((group) => places[group].includes(ext)) ?? ""
}

/** Which place shows the argument, by its name alone (a remote file is not read first), as the app's
 *  `ExplorerPlace` reads places.json: a folder's tree; Markdown; text; Preview for the kinds it draws and the
 *  known kinds that are not text; else File, which shows the info view for a file that is not UTF-8. */
export function kind(arg: string): "files" | "file" | "preview" | "markdown" {
  if (arg.endsWith("/")) return "files"
  const ext = extension(arg)
  if (places.markdown.includes(ext)) return "markdown"
  if (!ext || places.text.includes(ext)) return "file"
  return drawn(arg) || places.binary.includes(ext) ? "preview" : "file"
}

/** A place's own handling of a landing when the card comes back to it. */
export type Reveal = ((at: string) => void) | undefined

/** Where an open goes, by the modifier keys: ⌘ a new tab, ⌥ a pane to the side, else the card itself. */
export type How = "card" | "tab" | "side"
export const how = (event: MouseEvent | KeyboardEvent): How => (event.metaKey ? "tab" : event.altKey ? "side" : "card")

/** A file, or a folder (its path ends in `/`), in the card (its next place), or behind it in a new tab or a pane to
 *  the side, the keyboard kept here: a folder in a File Explorer, a file in its default plugin. */
export const open = (oriel: Oriel, arg: string, how: How) =>
  void oriel.open(arg, { how, background: how !== "card" }).catch((error) => console.error(error))

/** A row's menu at the pointer: Open (Open as Root for a folder), Open in New Tab, Open to the Side. */
export async function menu(oriel: Oriel, event: MouseEvent, arg: string) {
  event.preventDefault()
  const picked = await oriel.menu.show([
    { value: "card", title: arg.endsWith("/") ? "Open as Root" : "Open" },
    { value: "tab", title: "Open in New Tab" },
    { value: "side", title: "Open to the Side" },
  ])
  if (picked) open(oriel, arg, picked as How)
}

/** SF Symbols as masks (`oriel.symbol`), each loaded once: CSS draws `--sf-<name with - for .>`. */
const loaded = new Set<string>()
export function symbols(oriel: Oriel, names: string[], size = 12) {
  for (const name of names.filter((name) => !loaded.has(name))) {
    loaded.add(name)
    void oriel.symbol(name, size).then(
      (url) => document.documentElement.style.setProperty(`--sf-${name.replaceAll(".", "-")}`, `url(${url})`),
      () => loaded.delete(name),
    )
  }
}

/** The last part of a path; `/` is its own. */
export const name = (path: string) => (path === "/" ? "/" : path.replace(/\/$/, "").split("/").pop() ?? "")

/** A file's breadcrumbs, the same for every kind of file: its path from its repository's root (the repository's name
 *  first), else from the home folder (`~` first), else from `/`. */
export async function trail(oriel: Oriel, path: string) {
  const root = await oriel.git.root(path.slice(0, path.lastIndexOf("/")) || "/").catch(() => null)
  // git names the root with its links resolved: `/tmp` is `/private/tmp`.
  const repo = root && [root, root.replace(/^\/private(?=\/)/, "")].find((each) => path.startsWith(`${each}/`))
  // ponytail: the home folder where macOS and Linux put it; ask the machine if one lives elsewhere.
  const home = /^\/(?:Users\/(?!Shared\/)|home\/)[^/]+(?=\/)|^\/root(?=\/)/.exec(path)?.[0]
  // A home folder kept in git (dotfiles) reads from `~`.
  const base = (repo !== home && repo) || home || ""
  return [base === home ? "~" : base ? name(base) : "/", ...path.slice(base.length).split("/").filter(Boolean)]
}
