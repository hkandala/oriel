// A card's line to the app (Oriel/Plugins/Web/WebCard.swift).

/** The info view's facts of a file not shown: its name, size, kind and the system's icon. */
export type Info = { name: string; size: string; kind: string; icon: string }
/** `read`: the card's file, as its kind shows it (Oriel/Plugins/File/Document.swift). */
export type FileReply = { text: string; readOnly: boolean } | { info: Info }
export type PreviewReply = { type: string; data: string } | { info: Info }

type Ask = { op: "read" }
/**
 * `open`: a new tab; with no kind, `arg` is a file opened with its kind; `at` its landing (`at` below). `save`: the
 * editor's text, to disk.
 */
type Report =
  | { op: "dirty"; dirty: boolean }
  | { op: "open"; kind?: string; arg: string; at?: string }
  | { op: "save"; text: string }
  | { op: "symbol"; symbol: string }
  | { op: "page"; page: number; pages: number }
/** From the app: row 2's controls, menu commands, and the file again after a change on disk. */
export type In =
  | ({ op: "load" } & (FileReply | PreviewReply))
  | { op: "saved" | "save" | "find" }
  | { op: "zoom"; to: "fit" | "actual" | "in" | "out" }

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

/** Rejects with the app's error text; the reply's type is the ask's. */
export const ask = (message: Ask) => host.postMessage(message) as Promise<any>

export const report = (message: Report) => void host.postMessage(message)

/** Hears row 2's controls. */
export const receive = (handler: (message: In) => void) => {
  window.receive = handler
}
