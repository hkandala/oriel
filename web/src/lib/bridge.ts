// A card's line to the app (Oriel/Plugins/Web/WebCard.swift).

type Ask = { op: "read"; path: string }
/** `open`: a new tab; with no kind, `arg` is a file opened with its kind. */
type Report = { op: "dirty"; dirty: boolean } | { op: "open"; kind?: string; arg: string }
/** From row 2's controls (`WebCard.send`). */
type In = never

declare global {
  interface Window {
    card: { arg: string }
    receive?: (message: In) => void
    webkit: { messageHandlers: { oriel: { postMessage(message: Ask | Report): Promise<unknown> } } }
  }
}

const host = window.webkit.messageHandlers.oriel

/** The pane label's argument: the card's path or root. */
export const arg = window.card.arg

/** Rejects with the app's error text. */
export const ask = (message: Ask) => host.postMessage(message) as Promise<{ text: string }>

export const report = (message: Report) => void host.postMessage(message)

/** Hears row 2's controls. */
export const receive = (handler: (message: In) => void) => {
  window.receive = handler
}
