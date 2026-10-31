// A card's line to the app (Oriel/Plugins/Web/WebCard.swift).

/** The info view's facts of a file not shown: its name, size, kind and the system's icon. */
export type Info = { name: string; size: string; kind: string; icon: string }
/** `read`: the card's file, as its kind shows it (Oriel/Plugins/File/Document.swift). */
export type FileReply = { text: string; readOnly: boolean } | { info: Info }
export type PreviewReply = { type: string; data: string; fallback: Info } | { info: Info }
/** A folder's entry (`list`). */
export type Entry = { name: string; folder: boolean; ignored: boolean }
/** A changed file from the repository's root (`git`, the tree's letters), its letter as `Git.Change`'s. */
export type Change = { letter: string; path: string; oldPath?: string | null }
/** A commit with its row of the history graph (`repo`): lanes as `Git.GraphRow`'s, `date` in ms. */
export type Commit = {
  hash: string
  subject: string
  author: string
  /** As git's `%D` with `--decorate=full`: `HEAD -> refs/heads/main`, `refs/remotes/origin/main`, `tag: refs/tags/v1`. */
  refs: string[]
  date: number
  lane: number
  children: number[]
  parents: number[]
  through: number[]
}

/** The Git home's part (Oriel/Plugins/Git/GitRepo.swift); `failure` when the root is no repository. */
export type RepoState = {
  root: string
  staged?: Change[]
  unstaged?: Change[]
  commits?: Commit[]
  failure?: string
}

/** `patch`: a diff's patch as git prints it, its repo's root, and row 2's state. */
export type PatchReply = { patch: string; root: string; split: boolean; list: boolean; symbols: Record<string, string> }

/** `list`, `paths` and `git`: the File Explorer's root (Oriel/Plugins/Files/FilesCard.swift). */
type Ask =
  | { op: "read" }
  | { op: "patch" }
  | { op: "list"; path: string }
  | { op: "paths" }
  | { op: "git" }
  /** The Git home: its state and SF Symbols (`read`), or a write, answered once done. */
  | { op: "repo"; do: "read" | "draft" | "stage" | "unstage" | "stageAll" | "unstageAll" | "commit"; path?: string
      oldPath?: string | null; message?: string }
/**
 * `open`: `arg` in the card, a new tab or a pane to its side (`how`, the card by default); with no kind, in a File
 * Explorer; `at` its landing (`at` below). `save`: the editor's text, to disk. `filter`: the tree ended its filter.
 */
type Report =
  | { op: "dirty"; dirty: boolean }
  | { op: "open"; kind?: string; arg: string; at?: string; how?: How }
  | { op: "save"; text: string }
  | { op: "symbol"; symbol: string }
  | { op: "page"; page: number; pages: number }
  | { op: "filter"; text: string }
  /** The first rows or the file drew: the app's loader goes. */
  | { op: "ready" }
  /** The app's menu for a row (`menu` below). */
  | { op: "menu"; kind?: string; arg: string; at?: string; folder?: boolean }
  /** What the Markdown page shows. */
  | { op: "markdown"; edit: boolean; outline: boolean }
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
  | { op: "markdown"; edit: boolean; outline: boolean }
  /** The place shown again with another landing: a line, or a path to show in the tree. */
  | { op: "reveal"; at: string }
  /** The Git home's new state, after a change in the work tree or a write. */
  | { op: "repo"; repo: RepoState }

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

/** Where an open goes, by the modifier keys: ⌘ a new tab, ⌥ a pane to the side, else the card itself. */
export type How = "here" | "tab" | "side"
export const how = (event: MouseEvent | KeyboardEvent): How => (event.metaKey ? "tab" : event.altKey ? "side" : "here")

/** A row's menu, drawn by the app at the pointer: Open (Open as Root for a folder), Open in New Tab, Open to the
 *  Side. With no kind, in a File Explorer. */
export const menu = (event: MouseEvent, target: { kind?: string; arg: string; at?: string; folder?: boolean }) => {
  event.preventDefault()
  report({ op: "menu", ...target })
}

/** The app's SF Symbols (name → PNG data URL) as `--sf-<name>` masks; in a style sheet: the app sets the root's own
 *  style. */
export const symbols = (urls: Record<string, string>) => {
  const sheet = document.createElement("style")
  sheet.textContent = `:root { ${Object.entries(urls).map(([name, url]) => `--sf-${name.replaceAll(".", "-")}: url(${url});`).join(" ")} }`
  document.head.append(sheet)
}

/** Rejects with the app's error text; the reply's type is the ask's. */
export const ask = (message: Ask) => host.postMessage(message) as Promise<any>

export const report = (message: Report) => void host.postMessage(message)

/** Hears row 2's controls. */
export const receive = (handler: (message: In) => void) => {
  window.receive = handler
}
