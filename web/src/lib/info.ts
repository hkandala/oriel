// The info view of a file not shown (File and Preview): its icon, name, size and kind, in place of `parent`'s content.
import type { Info } from "./bridge"

export const info = (file: Info, parent: HTMLElement) => {
  const view = document.createElement("div")
  view.className = "info"
  const icon = Object.assign(document.createElement("img"), { src: file.icon, alt: "" })
  const name = Object.assign(document.createElement("div"), { className: "name", textContent: file.name })
  const facts = Object.assign(document.createElement("div"), { textContent: `${file.kind} · ${file.size}` })
  view.append(icon, name, facts)
  parent.replaceChildren(view)
}

/** The app's error text (the file is gone, or not a file), in the info view's place. */
export const failed = (error: unknown, parent: HTMLElement) => {
  const text = error instanceof Error ? error.message : String(error)
  parent.replaceChildren(Object.assign(document.createElement("div"), { className: "info", textContent: text }))
}
