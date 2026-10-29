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
