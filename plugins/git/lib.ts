// What the home and the diff share: the card's `oriel`, its places, opens and elements.
import type { Oriel } from "@oriel/plugin-api"

export let oriel: Oriel
export const bind = (api: Oriel) => {
  oriel = api
}

/** A place: the home is the root with the `/` of a folder, a diff `<home> <source>` (`PaneLabel.diff`). The root
 *  comes without its `/`, but `/` itself. */
export function parse(arg: string) {
  const space = arg.lastIndexOf(" "), diff = space > 0 && arg.slice(0, space).endsWith("/")
  const folder = diff ? arg.slice(0, space) : arg
  return { root: folder.length > 1 && folder.endsWith("/") ? folder.slice(0, -1) : folder,
    source: diff ? arg.slice(space + 1) : undefined }
}

export const home = (root: string) => (root.endsWith("/") ? root : `${root}/`)

/** Where an open goes, by the modifier keys: ⌘ a new tab, ⌥ a pane to the side, else the card itself. */
export type How = "card" | "tab" | "side"
export const how = (event: MouseEvent | KeyboardEvent): How => (event.metaKey ? "tab" : event.altKey ? "side" : "card")

/** A place of this card (a diff), or with no plugin a file in its default plugin. */
export const open = (arg: string, options: { how: How; at?: string; plugin?: string }) =>
  void oriel.open(arg, options).catch((error) => console.error(error))

/** A row's menu at the pointer: Open, Open in New Tab, Open to the Side. */
export async function menu(event: MouseEvent, arg: string, at?: string) {
  event.preventDefault()
  const picked = await oriel.menu.show([
    { value: "card", title: "Open" }, { value: "tab", title: "Open in New Tab" }, { value: "side", title: "Open to the Side" },
  ])
  if (picked) open(arg, { how: picked as How, at, plugin: "git" })
}

export function element<K extends keyof HTMLElementTagNameMap>(tag: K, className = "", text = "") {
  const node = document.createElement(tag)
  node.className = className
  node.textContent = text
  return node
}

/** An SF Symbol as a mask in the text's color (`--sf-<name>`, set by `main`). */
export function symbol(name: string, className = "symbol") {
  const node = element("span", className)
  node.style.setProperty("--symbol", `var(--sf-${name.replaceAll(".", "-")})`)
  node.ariaHidden = "true"
  return node
}

/** The card's state: the commit message typed, and the diff's file list shown. */
export const keep = (change: { draft?: string; list?: boolean }) =>
  oriel.state.set({ ...oriel.state.get<object>(), ...change })

/** git's message in the card's toast, on one line, with Copy for the whole of it. */
export async function failed(error: Error) {
  const text = error.message.split("\n").map((line) => line.trim()).join(" ")
  if ((await oriel.toast(text, ["Copy", "OK"])) === "Copy") await oriel.clipboard.write(error.message)
}

/** A header control's change, sent only when it changes something. */
const sent = new Map<string, string>()
export function control(id: string, change: Parameters<Oriel["controls"]["set"]>[1]) {
  const json = JSON.stringify({ ...JSON.parse(sent.get(id) ?? "{}"), ...change })
  if (sent.get(id) === json) return
  sent.set(id, json)
  oriel.controls.set(id, change)
}
