// What the home and the diff share: the card's `ovvi`, its places, opens and elements.
import type { Ovvi } from "@ovvi/plugin-api"
import { createFileTreeIconResolver, getBuiltInSpriteSheet } from "@pierre/trees"
import { ensureFileTreeStyles } from "@pierre/trees/web-components"

export let ovvi: Ovvi
export const bind = (api: Ovvi) => {
  ovvi = api
}

/** A place: the home is the root with the `/` of a folder, a diff `<home> <source>` (`PaneLabel.diffSource`). The root
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

/** A place of this card (a diff), or with no plugin a file in its default plugin; a new tab or a pane to the side opens
 *  behind, the keyboard kept here. A file's open in the card is a new tab in front. */
export const open = (arg: string, options: { how: How; at?: string; plugin?: string }) =>
  void ovvi.open(arg, { ...options, background: options.how !== "card" }).catch((error) => console.error(error))

/** A row's menu at the pointer: Open, Open in New Tab, Open to the Side. */
export async function menu(event: MouseEvent, arg: string, at?: string) {
  event.preventDefault()
  const picked = await ovvi.menu.show([
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

/** A path's name and its folder ("" at the top). */
export function nameAndFolder(path: string): [string, string] {
  const slash = path.lastIndexOf("/")
  return [path.slice(slash + 1), path.slice(0, Math.max(slash, 0))]
}

/** An SF Symbol as a mask in the text's color (`--sf-<name>`, set by `main`). */
export function symbol(name: string, className = "symbol") {
  const node = element("span", className)
  node.style.setProperty("--symbol", `var(--sf-${name.replaceAll(".", "-")})`)
  node.ariaHidden = "true"
  return node
}

const icons = createFileTreeIconResolver("complete")
let sprite: Document | undefined

/** A file's icon by its type, in its color, as File Explorer's tree draws it: the tree's own icons and stylesheet
 *  (`@pierre/trees`), in a shadow root of its own, where the tree's colors apply. */
export function fileIcon(path: string) {
  sprite ??= new DOMParser().parseFromString(getBuiltInSpriteSheet("complete"), "text/html")
  const { name, token } = icons.resolveIcon("file-tree-icon-file", path), shape = sprite.getElementById(name)
  const node = element("span", "file-icon"), root = node.attachShadow({ mode: "open" })
  node.ariaHidden = "true"
  ensureFileTreeStyles(root)
  root.innerHTML = `<div data-file-tree-colored-icons="true"><svg data-icon-token="${token ?? ""}" width="16" height="16"
    style="display: block" viewBox="${shape?.getAttribute("viewBox") ?? "0 0 16 16"}">${shape?.innerHTML ?? ""}</svg></div>`
  return node
}

/** The card's state: the commit message typed, and the diff's file list shown. */
export const keep = (change: { draft?: string; list?: boolean }) =>
  ovvi.state.set({ ...ovvi.state.get<object>(), ...change })

/** git's message in the card's toast, on one line, with Copy for the whole of it. */
export async function failed(error: Error) {
  const text = error.message.split("\n").map((line) => line.trim()).join(" ")
  if ((await ovvi.toast(text, ["Copy", "OK"])) === "Copy") ovvi.clipboard.write(error.message).catch(console.error)
}
