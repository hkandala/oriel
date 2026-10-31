// What every place of the card gets from `main.ts`, and the open gestures they share.
import type { Off, Oriel } from "@oriel/plugin-api"

export type Place = {
  oriel: Oriel
  /** The place's argument: a folder's path with its `/`, or a file's path. */
  arg: string
  /** A linked open's landing: a line, or the path to reveal in the tree. */
  at?: string
  /** The place draws in here; `main.ts` shows it once `show` returned. */
  root: HTMLElement
  /** Ends with the place: a handler's or a watch's `Off`, a view's teardown. */
  keep(off: Off): void
  /** Shows the place anew, as it first showed: its file became read only or too large. */
  again(): void
}

/** A place's own handling of the same place with another landing. */
export type Reveal = ((at: string) => void) | undefined

/** Where an open goes, by the modifier keys: ⌘ a new tab, ⌥ a pane to the side, else the card itself. */
export type How = "card" | "tab" | "side"
export const how = (event: MouseEvent | KeyboardEvent): How => (event.metaKey ? "tab" : event.altKey ? "side" : "card")

/** A file, or a folder (its path ends in `/`), in the card (its next place), a new tab or a pane to the side: a
 *  folder in a File Explorer, a file in its default plugin. */
export const open = (oriel: Oriel, arg: string, how: How) =>
  void oriel.open(arg, { how }).catch((error) => console.error(error))

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

/** The last part of a path; `/` is its own. */
export const name = (path: string) => (path === "/" ? "/" : path.replace(/\/$/, "").split("/").pop() ?? "")
