// A card's line to the app (Oriel/Plugins/Web/WebCard.swift).

type Ask = { op: "read"; path: string }
/** `open`: a new tab; with no kind, `arg` is a file opened with its kind; `at` its landing (`at` below). */
type Report = { op: "dirty"; dirty: boolean } | { op: "open"; kind?: string; arg: string; at?: string }
/** From row 2's controls (`WebCard.send`). */
type In = never

declare global {
  interface Window {
    card: { arg: string; at?: string }
    receive?: (message: In) => void
    webkit: { messageHandlers: { oriel: { postMessage(message: Ask | Report): Promise<unknown> } } }
  }
}

const host = window.webkit.messageHandlers.oriel

/** The pane label's argument: the card's path or root. */
export const arg = window.card.arg

/** A linked open's landing, on the first load only: a file's 1-based line, or a diff's file from the repo's root. */
export const at = window.card.at

/** Rejects with the app's error text. */
export const ask = (message: Ask) => host.postMessage(message) as Promise<{ text: string }>

export const report = (message: Report) => void host.postMessage(message)

/** Hears row 2's controls. */
export const receive = (handler: (message: In) => void) => {
  window.receive = handler
}
