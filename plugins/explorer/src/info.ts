// The info view of a file not shown (File and Preview): its icon, name, size and kind, in place of `parent`'s content.
import type { Oriel } from "@oriel/plugin-api"

/** A size as the Finder writes it (`ByteCountFormatter`'s file style): 950 bytes, 3 kB, 1.2 MB, 1.23 GB. */
export function size(bytes: number) {
  if (bytes === 0) return "Zero kB"
  if (bytes < 999) return bytes === 1 ? "1 byte" : `${bytes} bytes`
  let value = bytes / 1000, unit = 0
  while (value >= 999 && unit < 3) {
    value /= 1000
    unit++
  }
  return `${Number(value.toFixed([0, 1, 2, 2][unit]))} ${["kB", "MB", "GB", "TB"][unit]}`
}

/** The file's facts from the app; its error text when there is no file to tell of. */
export async function info(oriel: Oriel, path: string, parent: HTMLElement) {
  const file = await oriel.files.info(path).catch((error) => failed(error, parent))
  if (!file) return
  const view = document.createElement("div")
  view.className = "info"
  const icon = Object.assign(document.createElement("img"), { src: file.icon, alt: "" })
  const name = Object.assign(document.createElement("div"), { className: "name", textContent: file.name })
  const facts = Object.assign(document.createElement("div"), { textContent: `${file.kind} · ${size(file.size)}` })
  view.append(icon, name, facts)
  parent.replaceChildren(view)
}

/** The app's error text (the file is gone, or not a file), in the info view's place. */
export const failed = (error: unknown, parent: HTMLElement) => {
  const text = error instanceof Error ? error.message : String(error)
  parent.replaceChildren(Object.assign(document.createElement("div"), { className: "info", textContent: text }))
}
