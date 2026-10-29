// A card's line to the app (Oriel/Plugins/Web/WebCard.swift).

type Ask = { op: "read"; path: string }
type Report = { op: "dirty"; dirty: boolean }

declare global {
  interface Window {
    card: { arg: string }
    webkit: { messageHandlers: { oriel: { postMessage(message: Ask | Report): Promise<unknown> } } }
  }
}

const host = window.webkit.messageHandlers.oriel

/** The pane label's argument: the card's path or root. */
export const arg = window.card.arg

/** Rejects with the app's error text. */
export const ask = (message: Ask) => host.postMessage(message) as Promise<{ text: string }>

export const report = (message: Report) => void host.postMessage(message)
