// A card's line to the app (Oriel/Plugins/Web/WebCard.swift).

/** The info view's facts of a file not shown: its name, size, kind and the system's icon. */
export type Info = { name: string; size: string; kind: string; icon: string }
/** `read`: the card's file, as its kind shows it (Oriel/Plugins/File/Document.swift). */
export type FileReply = { text: string; readOnly: boolean } | { info: Info }
export type PreviewReply = { type: string; data: string; fallback: Info } | { info: Info }
/** A folder's entry (`list`). */
export type Entry = { name: string; folder: boolean; ignored: boolean }
/** A changed file from the repository's root (`git`), its letter as `Git.Change`'s. */
export type Change = { letter: string; path: string }
/** A commit with its row of the history graph (`git`): lanes as `Git.GraphRow`'s, `date` in ms. */
export type Commit = {
  hash: string
  subject: string
  date: number
  lane: number
  children: number[]
  parents: number[]
  through: number[]
}

/** `patch`: a diff's patch as git prints it, its repo's root, and row 2's state. */
export type PatchReply = { patch: string; root: string; split: boolean; list: boolean }

/** `list`, `paths` and `git`: the Files card's root (Oriel/Plugins/Files/FilesCard.swift). */
type Ask =
  | { op: "read" }
  | { op: "patch" }
  | { op: "list"; path: string; repo?: string }
  | { op: "paths"; repo?: string }
  | { op: "git" }
/**
 * `open`: a new tab; with no kind, `arg` is a file opened with its kind; `at` its landing (`at` below). `save`: the
 * editor's text, to disk. `filter`: the Files card ended its filter.
 */
type Report =
  | { op: "dirty"; dirty: boolean }
  | { op: "open"; kind?: string; arg: string; at?: string }
  | { op: "save"; text: string }
  | { op: "symbol"; symbol: string }
  | { op: "page"; page: number; pages: number }
  | { op: "filter"; text: string }
/** From the app: row 2's controls, menu commands, and the file again after a change on disk. */
export type In =
  | ({ op: "load" } & (FileReply | PreviewReply))
  | { op: "saved" | "save" | "find" | "findNext" | "findPrevious" }
  | { op: "zoom"; to: "fit" | "actual" | "in" | "out" }
  | { op: "layout"; split: boolean }
  | { op: "list"; open: boolean }
  | { op: "step"; by: 1 | -1 }
  /** The work tree changed: a diff asks for the patch again, Files lists its open folders again. */
  | { op: "changed" }
  | { op: "filter"; text: string }
  | { op: "collapse" }

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
