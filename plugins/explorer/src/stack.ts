// The tree's sticky folders (Pierre's sticky stack) on the card itself, with no band of their own: an opaque band never
// matches Glass's card, whose fill changes with what is behind the window. The tree's scroll view is masked under the
// stack, so no row shows there at any scroll speed: the mask stays with the view, which does not scroll, while WebKit
// moves the rows on its own thread. The stack is in the view, so it is masked too; a copy of it draws over the mask,
// after each draw of the tree (the stack's rows change only then). The stack itself still takes the clicks.

/** Shows the stack of the tree in `host` (a `FileTree`'s container) as a copy over its masked view. */
export function stack(host: HTMLElement) {
  const shadow = host.shadowRoot!
  const copy = shadow.appendChild(document.createElement("div"))
  copy.dataset.stackCopy = ""
  // Out of the way of clicks, the keyboard and VoiceOver: the stack below takes them.
  copy.inert = true
  let drawn = "", hovered: string | null = null
  /** The hover the stack's row has, on its copy. */
  const hover = () => {
    for (const row of copy.querySelectorAll<HTMLElement>("[data-file-tree-sticky-path]")) {
      row.toggleAttribute("data-hover", row.dataset.fileTreeStickyPath === hovered)
    }
  }
  const draw = () => {
    const overlay = shadow.querySelector<HTMLElement>("[data-file-tree-sticky-overlay]")
    const content = overlay?.firstElementChild as HTMLElement | null | undefined
    // At the top, Pierre hides the stack (but while a scroll lands there).
    const shown = content && getComputedStyle(overlay!).visibility !== "hidden" ? content : null
    const html = shown?.outerHTML ?? ""
    if (html === drawn) return
    drawn = html
    host.toggleAttribute("data-stack", Boolean(shown))
    host.style.setProperty("--stack", `${shown?.offsetHeight ?? 0}px`)
    copy.replaceChildren(...(shown ? [shown.cloneNode(true)] : []))
    if (!shown) return
    const box = shown.getBoundingClientRect(), base = host.getBoundingClientRect()
    Object.assign(copy.style, { top: `${box.top - base.top}px`, left: `${box.left - base.left}px`, width: `${box.width}px` })
    // A nested folder that the next one pushes up goes under its parent: cut where the rows above end.
    let bottom = 0
    for (const row of copy.firstElementChild!.children as HTMLCollectionOf<HTMLElement>) {
      if (row.offsetTop < bottom) row.style.clipPath = `inset(${bottom - row.offsetTop}px 0 0 0)`
      bottom = Math.max(bottom, row.offsetTop + row.offsetHeight)
    }
    hover()
  }
  // Pierre's draws come in a microtask after its scroll handler, so the copy and the mask change in the same frame. A
  // new width (a split's divider, the window) moves the copy.
  new MutationObserver(draw).observe(shadow, { subtree: true, childList: true, attributes: true })
  new ResizeObserver(() => {
    drawn = ""
    draw()
  }).observe(host)
  for (const type of ["pointerover", "pointerout"]) {
    shadow.addEventListener(type, (event) => {
      const row = (event.target as Element).closest?.("[data-file-tree-sticky-path]")
      hovered = type === "pointerover" ? row?.getAttribute("data-file-tree-sticky-path") ?? null : null
      hover()
    })
  }
}
