// What every place of the card gets from `main.ts`, and the open gestures they share.
import type { Off, Ovvi } from "@ovvi/plugin-api"
import places from "../places.json"

export type Place = {
  /** The page's own: its handlers, watches and header controls wait while it is hidden (`ovvi.pages`). */
  ovvi: Ovvi
  /** The place's argument: a folder's path with its `/`, or a file's path. */
  arg: string
  /** A linked open's landing: a line, or the path to reveal in the tree. */
  at?: string
  /** The page: the place draws in here; it shows once `show` returned. */
  root: HTMLElement
  /** Ends with the place: a view's teardown. `ovvi`'s handlers and watches end with it on their own. */
  keep(off: Off): void
  /** Shows the place anew, as it first showed: its file became read only or too large. */
  again(): void
  /** The card keeps the page: work that ends after it dropped does nothing. */
  live(): boolean
  /** The page shows: a hidden one leaves the keyboard and the clipboard alone. */
  shown(): boolean
  /** File's and Markdown's file, read already. */
  read?: ReturnType<Ovvi["files"]["read"]>
  /** A file's breadcrumbs (`trail`); none for a folder. */
  trail: string[]
}

/** The card's own choices in its header, kept in its state: they win over the settings, which start new cards. */
export type Own = { hiddenFiles?: boolean; mode?: string; locked?: boolean; preview?: boolean; wrap?: boolean }
export const own = (ovvi: Ovvi) => ovvi.state.get<Own>() ?? {}
export const choose = (ovvi: Ovvi, change: Own) => ovvi.state.set({ ...ovvi.state.get<object>(), ...change })

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
export const open = (ovvi: Ovvi, arg: string, how: How) =>
  void ovvi.open(arg, { how, background: how !== "card" }).catch((error) => console.error(error))

/** A row's or a link's menu at the pointer: Open (Open as Root for a folder), Open in New Tab, Open to the Side;
 *  Rename when the row can be renamed; a link's Copy Link, as WebKit's own menu had. */
export async function menu(ovvi: Ovvi, event: MouseEvent, arg: string, more: { rename?: () => void; link?: boolean } = {}) {
  event.preventDefault()
  const picked = await ovvi.menu.show([
    { value: "card", title: arg.endsWith("/") ? "Open as Root" : "Open" },
    { value: "tab", title: "Open in New Tab" },
    { value: "side", title: "Open to the Side" },
    ...(more.rename ? ["-" as const, { value: "rename", title: "Rename" }] : []),
    ...(more.link ? ["-" as const, { value: "copy", title: "Copy Link" }] : []),
  ])
  if (picked === "rename") more.rename?.()
  else if (picked === "copy") ovvi.clipboard.write(arg).catch(console.error)
  else if (picked) open(ovvi, arg, picked as How)
}

/** SF Symbols as masks (`ovvi.symbol`), each loaded once: CSS draws `--sf-<name with - for .>`. In a sheet of their
 *  own: the app sets the root's inline style to its colors on each theme change (a new tab's too), which drops any
 *  property set there. */
const loaded = new Set<string>()
const sheet = document.head.appendChild(document.createElement("style")).sheet!
export function symbols(ovvi: Ovvi, names: string[], size = 12) {
  for (const name of names.filter((name) => !loaded.has(name))) {
    loaded.add(name)
    void ovvi.symbol(name, size).then(
      (url) => sheet.insertRule(`:root { --sf-${name.replaceAll(".", "-")}: url(${url}) }`),
      () => loaded.delete(name),
    )
  }
}

/** The last part of a path; `/` is its own. */
export const name = (path: string) => (path === "/" ? "/" : path.replace(/\/$/, "").split("/").pop() ?? "")

/** A file's breadcrumbs, the same for every kind of file: its path from its repository's root (the repository's name
 *  first), else from the home folder (`~` first), else from `/`. */
export async function trail(ovvi: Ovvi, path: string) {
  const root = await ovvi.git.root(path.slice(0, path.lastIndexOf("/")) || "/").catch(() => null)
  // git names the root with its links resolved: `/tmp` is `/private/tmp`.
  const repo = root && [root, root.replace(/^\/private(?=\/)/, "")].find((each) => path.startsWith(`${each}/`))
  // ponytail: the home folder where macOS and Linux put it; ask the machine if one lives elsewhere.
  const home = /^\/(?:Users\/(?!Shared\/)|home\/)[^/]+(?=\/)|^\/root(?=\/)/.exec(path)?.[0]
  // A home folder kept in git (dotfiles) reads from `~`.
  const base = (repo !== home && repo) || home || ""
  return [base === home ? "~" : base ? name(base) : "/", ...path.slice(base.length).split("/").filter(Boolean)]
}
