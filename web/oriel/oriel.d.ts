// The plugin API, version 1 (plugins/api): the object a plugin's entry gets. The app ships it as the host
// types package `@oriel/plugin-api`; a plugin lists that in `peerDependencies` as "*" and imports only its types:
//
//   import type { Oriel } from "@oriel/plugin-api"
//   export default async function main(oriel: Oriel) { … }
//
// A member added after version 1 says `@since <api>`.

export interface Oriel {
  /** The API version the app gives this page: the manifest's `api`. */
  readonly api: number
  readonly card: Card
  readonly files: Files
  readonly git: Git
  readonly state: State
  readonly controls: Controls
  readonly theme: Theme
  /** Needs `clipboard`. */
  readonly clipboard: { write(text: string): Promise<void> }
  /** The native context menu at the pointer. Resolves with the picked item's value, or undefined. */
  readonly menu: { show(items: MenuItem[]): Promise<string | undefined> }
  /** Choose Folder…: the Mac's folder panel, a folder field on a remote machine. Resolves with the folder's path, or
   *  undefined. */
  readonly pick: { folder(from?: string): Promise<string | undefined> }

  /** Runs argv on the card's machine, in the pane's folder unless `cwd` says otherwise: no shell, 30 s unless
   *  `timeout` (ms) says otherwise, 4 MiB of stdout, two at a time per card. Needs `run`. */
  run(argv: string[], options?: { cwd?: string; stdin?: string; timeout?: number }): Promise<RunResult>
  /** An open of a file, a folder (ends in `/`), a URL or a plugin's argument: in this card, in a new tab right after
   *  this card's tab (the default) or in a pane to its side. No `plugin`: the file's default plugin, the browser for
   *  a web address. `at`: the new card's landing (`card.at`). */
  open(arg: string, options?: { plugin?: string; how?: "card" | "tab" | "side"; at?: string }): Promise<void>
  /** One line on glass at the top of the card, with `buttons` (the second the default) or OK. Resolves with the title
   *  picked, or undefined when another toast took its place. */
  toast(text: string, buttons?: [other: string, main: string]): Promise<string | undefined>
  /** An SF Symbol as a PNG data URL, `size` points tall (16 by default), black on clear: use it as a mask. */
  symbol(name: string, size?: number): Promise<string>

  /** A header control or a command, as the user changed it: a click (no value), a toggle, a segment, a menu item, a
   *  field's text (`submit` on Return). */
  on(event: "control", fn: (e: { id: string; value?: string | boolean; submit?: boolean }) => void): Off
  /** The card moved to another place: after `card.go`, Back, Forward, or a rename from elsewhere. After Back, `at`
   *  is the place it came back from: that place's landing, else its argument. */
  on(event: "place", fn: (place: { arg: string; at?: string }) => void): Off
  /** ⌘S, ⌘F, ⌘G, ⇧⌘G over the card, with `handles` in the manifest. */
  on(event: "save" | "find" | "findNext" | "findPrevious", fn: () => void): Off
  on(event: "visible" | "keyboard", fn: (yes: boolean) => void): Off
  on(event: "theme", fn: (theme: Theme) => void): Off
}

/** Stops the handler or the watch. Every one ends with the page. */
export type Off = () => void

export interface Card {
  /** The instance id from the label: stable for the pane's life. */
  readonly id: string
  readonly plugin: { id: string; version: string }
  readonly machine: { id: string; name: string; remote: boolean }
  /** The place: the label's argument (a path, a root, "<root> <source>", a URL, or ""). */
  readonly arg: string
  /** The pane's folder on its machine. */
  readonly cwd: string
  /** A linked open's landing, on the first load only: a 1-based line, or a file of a diff. */
  readonly at?: string
  readonly visible: boolean
  readonly keyboard: boolean
  /** Moves the card to another place: the label follows, the app keeps Back and Forward. With unsaved edits the app
   *  asks first. The page hears `place` once it moved; it is not loaded again. */
  go(arg: string, options?: { at?: string }): void
  /** Ends the card's loader. Also when `main` returns. */
  ready(): void
  /** The Edited dot after the title. A dirty card is never dropped; a move or a close asks Discard or Keep Editing. */
  setDirty(dirty: boolean): void
}

export interface Files {
  /** UTF-8 text up to 16 MB. `hash` is what `write` checks. `writable` is false over 4 MiB on a remote machine. */
  read(path: string): Promise<{ text: string; hash: string; writable: boolean }>
  /** Bytes up to 16 MB, with the MIME type from the name. */
  readBytes(path: string): Promise<{ data: Uint8Array; type: string; hash: string }>
  /** The info view's facts: the size in bytes, the kind's name, the system's icon as a PNG data URL; and the hash
   *  `read` gives (none for a folder), to tell a change without reading the file. */
  info(path: string): Promise<{ name: string; size: number; kind: string; icon: string; folder: boolean; hash: string }>
  /** A folder's entries but `.git`, folders first, by name as the Finder sorts; `ignored` when git ignores it. */
  list(folder: string): Promise<{ name: string; folder: boolean; ignored: boolean }[]>
  /** Every file under the root, from it: the files git does not ignore in a repository, else every file, up to 8 MB
   *  of names. */
  paths(root: string): Promise<string[]>
  /** Writes a new file beside the old one and moves it over. With `over`, fails with `changed` if the file's hash
   *  differs. Needs `files:write`. */
  write(path: string, data: string | Uint8Array, options?: { over?: string }): Promise<{ hash: string }>
  /** Calls fn after a change under path, only while the card shows, and once on showing again. */
  watch(path: string, fn: () => void): Off
}

/** Needs `git`. Writes run one at a time per card, and never ask for a password (they fail with git's message). */
export interface Git {
  /** The repository's root of a folder, or null. */
  root(folder: string): Promise<string | null>
  /** The changed files from the root, each untracked file on its own: the work tree's letter, else the index's. */
  status(root: string): Promise<Change[]>
  /** The changes as the index keeps them: staged (the index against HEAD) and unstaged (untracked included). */
  changes(root: string): Promise<{ staged: Change[]; unstaged: Change[] }>
  /** The checkout's branch (the short hash when detached) and how far it is from its upstream; null outside a
   *  repository. */
  head(root: string): Promise<{ branch: string; ahead: number; behind: number } | null>
  /** The local branches, then the remote ones with no local branch of their name. */
  branches(root: string): Promise<{ name: string; remote: boolean; current: boolean }[]>
  /** The last 500 commits of every branch, remote branch and tag, and HEAD, newest first, with the graph's lanes. */
  log(root: string, options?: { limit?: number }): Promise<Commit[]>
  /** The patch as git prints it: "uncommitted" (staged, unstaged and untracked against HEAD) or a commit against its
   *  first parent. Up to 16 MB. */
  diff(root: string, source: string): Promise<string>
  /** `git add -A` of the paths (literal, not patterns), or of everything. */
  stage(root: string, paths?: string[]): Promise<void>
  unstage(root: string, paths?: string[]): Promise<void>
  commit(root: string, message: string): Promise<void>
  fetch(root: string): Promise<void>
  /** git's own way (the user's `pull.rebase`). */
  pull(root: string): Promise<void>
  /** A branch with no upstream is published under its name. */
  push(root: string): Promise<void>
  /** A remote branch (`origin/x`) makes a local one that tracks it. */
  switch(root: string, branch: string): Promise<void>
}

export interface Change {
  /** M, A, D, R, C (a conflict), U (untracked); `status` also ? for untracked. */
  letter: string
  path: string
  oldPath?: string
}

export interface Commit {
  hash: string
  subject: string
  author: string
  /** As git's `%D` with `--decorate=full`: `HEAD -> refs/heads/main`, `refs/remotes/origin/main`, `tag: refs/tags/v1`. */
  refs: string[]
  /** Milliseconds since 1970. */
  date: number
  lane: number
  children: number[]
  parents: number[]
  through: number[]
}

export interface RunResult {
  code: number
  stdout: string
  /** The last 8 KB. */
  stderr: string
  /** stdout went past 4 MiB: the command was stopped there. */
  truncated: boolean
}

export interface State {
  /** The card's state as last set: given at load, also after a drop, a reload or a relaunch. */
  get<T>(): T | undefined
  /** JSON, at most 256 KiB. Kept at once in the app; written to the card's machine 500 ms after the last set. */
  set<T>(value: T): void
}

export interface Controls {
  /** A header control's current value. */
  get(id: string): string | boolean | string[] | undefined
  /** Changes a header control or a command. `badge` "" or 0 clears; `busy` shows a spinner in a button or a menu and
   *  disables the control. A field's value changes as the user types: set it only to replace or clear it (after
   *  submit), never to echo it. */
  set(id: string, change: {
    value?: string | boolean | string[]
    title?: string
    /** An SF Symbol: a button's or a toggle's icon, or drawn before a text's last part; "" clears. */
    symbol?: string
    /** What VoiceOver reads, when not the title ("Push, 1 ahead"); "" clears. */
    label?: string
    badge?: string | number
    items?: MenuItem[]
    hidden?: boolean
    enabled?: boolean
    checked?: boolean
    busy?: boolean
  }): void
}

/** An item, a section heading (no value) or a divider. */
export type MenuItem = { value: string; title: string; symbol?: string } | { title: string } | "-"

export interface Theme {
  dark: boolean
  style: "glass" | "classic"
  /** The app's text size in points (⌘+ ⌘− ⌘0). */
  textSize: number
  /** The app's tokens as CSS colors; also CSS variables on the root (`--text`, …), with `--app-text-size`. */
  /** `card` is an opaque stand-in for the card's fill, for a band that text scrolls under. */
  colors: Record<
    "text" | "dim" | "divider" | "card" | "accent" | "on-accent" | "working" | "needs-you" | "finished" | "error",
    string
  >
}

/** What every failed call rejects with. */
export interface OrielError extends Error {
  code: "denied" | "notFound" | "notText" | "tooLarge" | "changed" | "timeout" | "closed" | "failed"
}
