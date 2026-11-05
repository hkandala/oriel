// The runtime: the `oriel` object of a plugin's page (oriel.d.ts), made from the card's context the app puts in the
// page at document start, before the plugin's code runs. Its messages are the app's own (Oriel/Plugins/Bridge.swift):
// `{ call, args }` to the app, answered with JSON or rejected with "<code>: <text>"; `oriel_receive(name, data)` from
// it.
import type { Card, Controls, MenuItem, Off, Oriel, OrielError, Page, RunResult, Theme } from "./oriel"

type Context = {
  api: number
  id: string
  plugin: { id: string; version: string }
  machine: { id: string; name: string; remote: boolean }
  arg: string
  cwd: string
  at?: string
  visible: boolean
  keyboard: boolean
  state?: unknown
  controls: Record<string, string | boolean | string[]>
  theme: Theme
  /** The entry's built file, from the page's folder. */
  entry: string
}

declare global {
  interface Window {
    oriel_card: Context
    oriel_receive: (name: string, data: unknown) => void
    webkit: { messageHandlers: { oriel: { postMessage(message: unknown): Promise<string | null> } } }
  }
}

const context = window.oriel_card
const host = window.webkit.messageHandlers.oriel

async function call<T = void>(name: string, args: object = {}): Promise<T> {
  let reply: string | null
  try {
    reply = await host.postMessage({ call: name, args })
  } catch (error) {
    const text = String((error as Error).message ?? error), colon = text.indexOf(": ")
    const failure = new Error(colon > 0 ? text.slice(colon + 2) : text) as OrielError
    failure.code = (colon > 0 ? text.slice(0, colon) : "failed") as OrielError["code"]
    throw failure
  }
  return (reply == null ? undefined : JSON.parse(reply)) as T
}

/** A call whose promise nobody awaits: its failure goes to the console. */
const tell = (name: string, args: object = {}) => void call(name, args).catch((error) => console.error(error))

type Handler = (data: any) => void
const handlers = new Map<string, Set<Handler>>()
const watches = new Map<number, () => void>()
const toasts = new Map<number, (button: string | undefined) => void>()
let next = 0

window.oriel_receive = (name, data: any) => {
  switch (name) {
    case "watch":
      return watches.get(data)?.()
    case "toast":
      toasts.get(data.id)?.(data.button ?? undefined)
      return void toasts.delete(data.id)
    case "control":
      if ("value" in data) {
        context.controls[data.id] = data.value
        current?.controls.set(data.id, { ...current.controls.get(data.id), value: data.value })
      }
      break
    case "place":
      context.arg = data.arg
      if (draw) moved(data.arg, data.at)
      break
    case "visible":
    case "keyboard":
      if (context[name] === data) return
      context[name] = data
      break
    case "theme":
      context.theme = data
      break
  }
  handlers.get(name)?.forEach((fn) => fn(data))
}

const card: Card = {
  id: context.id,
  plugin: context.plugin,
  machine: context.machine,
  get arg() {
    return context.arg
  },
  cwd: context.cwd,
  at: context.at,
  get visible() {
    return context.visible
  },
  get keyboard() {
    return context.keyboard
  },
  go: (arg, options) => tell("card.go", { arg, at: options?.at }),
  ready: () => tell("card.ready"),
  setDirty(yes) {
    dirty = yes
    tell("card.setDirty", { dirty: yes })
  },
}

/** Each control as the page last set it in the app. A menu pick reaches the page's record of it, not the app's (the
 *  page sets a menu's value), so a page setting the picked value must still send it. */
const sent = new Map<string, Record<string, unknown>>()
/** The change says something the app's header was not told. */
const news = (id: string, change: Record<string, unknown>) => !same({ ...sent.get(id), ...change }, sent.get(id))

const controls: Controls = {
  get: (id) => context.controls[id],
  set(id, change) {
    if (change.value !== undefined) context.controls[id] = change.value
    const { focus, refused, ...rest } = change
    sent.set(id, { ...sent.get(id), ...rest })
    tell("controls.set", { id, change })
  },
}

const oriel: Oriel = {
  api: context.api,
  card,
  files: {
    read: (path) => call("files.read", { path }),
    async readBytes(path) {
      const reply = await call<{ base64: string; type: string; hash: string }>("files.readBytes", { path })
      return { data: Uint8Array.fromBase64(reply.base64), type: reply.type, hash: reply.hash }
    },
    info: (path) => call("files.info", { path }),
    list: (path) => call("files.list", { path }),
    paths: (path) => call("files.paths", { path }),
    write: (path, data, options) =>
      call("files.write", { path, over: options?.over, ...(typeof data === "string" ? { text: data } : { base64: data.toBase64() }) }),
    watch(path, fn) {
      const id = ++next
      watches.set(id, fn)
      tell("files.watch", { id, path })
      return () => {
        if (watches.delete(id)) tell("files.unwatch", { id })
      }
    },
  },
  git: {
    root: (folder) => call("git.root", { folder }),
    status: (root) => call("git.status", { root }),
    changes: (root) => call("git.changes", { root }),
    head: (root) => call("git.head", { root }),
    branches: (root) => call("git.branches", { root }),
    log: (root, options) => call("git.log", { root, limit: options?.limit }),
    diff: (root, source) => call("git.diff", { root, source }),
    show: (root, hash) => call("git.show", { root, source: hash }),
    stage: (root, paths) => call("git.stage", { root, paths }),
    unstage: (root, paths) => call("git.unstage", { root, paths }),
    revert: (root, paths) => call("git.revert", { root, paths }),
    commit: (root, message) => call("git.commit", { root, message }),
    fetch: (root) => call("git.fetch", { root }),
    pull: (root) => call("git.pull", { root }),
    push: (root) => call("git.push", { root }),
    switch: (root, branch) => call("git.switch", { root, branch }),
    init: (folder) => call("git.init", { root: folder }),
  },
  state: {
    get: <T>() => context.state as T | undefined,
    set(value) {
      context.state = value
      tell("state.set", { value })
    },
  },
  controls,
  get theme() {
    return context.theme
  },
  clipboard: { write: (text) => call("clipboard.write", { text }) },
  menu: { show: (items: MenuItem[]) => call("menu.show", { items }) },
  pick: { folder: (from) => call("pick.folder", { from }) },
  run: (argv, options) =>
    call<RunResult>("run", { argv, cwd: options?.cwd ?? context.cwd, stdin: options?.stdin, timeout: options?.timeout }),
  open: (arg, options) => call("open", { arg, ...options }),
  toast(text, buttons, options) {
    const id = ++next
    return new Promise((resolve) => {
      toasts.set(id, resolve)
      tell("toast", { id, text, buttons, options })
    })
  },
  symbol: (name, size) => call("symbol", { name, size }),
  on(event: string, fn: Handler) {
    const set = handlers.get(event) ?? new Set()
    handlers.set(event, set.add(fn))
    return () => void set.delete(fn)
  },
  pages: {
    async route(fn) {
      draw = fn
      addEventListener("keydown", backForward, true)
      await fill(context.arg, context.at)
    },
  },
}

// The card's pages (`oriel.pages`): a router over the card's places that keeps the pages it showed. A hidden page is
// `inert` (card.css hides it and keeps its layout and scroll); its handlers, watches and header controls wait.
type Kept = {
  page: Page
  offs: Off[]
  /** The header controls as the page left them: its own changes, the user's values, and the rest as at its first show. */
  controls: Map<string, Record<string, unknown>>
  /** Watches that fired while hidden: they run when it shows. */
  due: Set<() => void>
  /** Its `place` handlers: the card moved to it again. */
  places: Set<Handler>
  title?: string
  /** The landing of a move to it while it was still being drawn. */
  landing?: string
  shownOnce: boolean
  drawn: boolean
  dropped: boolean
}
/** Two records of a control, whose keys can come in different orders. */
const same = (a?: Record<string, unknown>, b?: Record<string, unknown>) =>
  JSON.stringify(a && Object.entries(a).sort()) === JSON.stringify(b && Object.entries(b).sort())
/** The events a hidden page hears too. */
const always = new Set(["theme", "visible"])
/** The pages drawn and being drawn, the last shown last. */
let pages: Kept[] = []
let current: Kept | undefined
let draw: ((page: Page) => Promise<void>) | undefined
let dirty = false

function make(arg: string, at?: string): Kept {
  const element = Object.assign(document.createElement("div"), { className: "oriel-page", inert: true })
  document.body.append(element)
  const own = (off: Off) => {
    kept.offs.push(off)
    return off
  }
  const scoped: Oriel = Object.create(oriel, {
    on: {
      value: (event: string, fn: Handler) => {
        if (event !== "place") return own(oriel.on(event as "control", (data) => (always.has(event) || current === kept) && fn(data)))
        kept.places.add(fn)
        return () => void kept.places.delete(fn)
      },
    },
    controls: {
      value: {
        get: (id) => (kept.controls.get(id)?.value ?? context.controls[id]) as ReturnType<Controls["get"]>,
        set(id, change) {
          // A focus or a shake is for now only.
          const { focus, refused, ...rest } = change
          const was = kept.controls.get(id) ?? {}, next = { ...was, ...rest }
          kept.controls.set(id, next)
          if (current === kept && (focus || refused || !same(next, was) || news(id, rest))) controls.set(id, change)
        },
      } satisfies Controls,
    },
    files: {
      value: Object.create(oriel.files, {
        watch: { value: (path: string, fn: () => void) => own(watch(path, () => (current === kept ? fn() : kept.due.add(fn)))) },
      }),
    },
  })
  const kept: Kept = {
    offs: [], controls: new Map(), due: new Set(), places: new Set(), shownOnce: false, drawn: false, dropped: false,
    page: {
      arg, at, element, oriel: scoped,
      get shown() {
        return current === kept
      },
      get dropped() {
        return kept.dropped
      },
      keep: (off) => void kept.offs.push(off),
      redraw: () => (current === kept ? void fill(arg) : drop(kept)),
    },
  }
  pages.push(kept)
  return kept
}

/** A new page for the place, shown once drawn (also when its draw failed) if the card is still there. */
async function fill(arg: string, at?: string) {
  const kept = make(arg, at)
  try {
    await draw?.(kept.page)
  } catch (error) {
    console.error(error)
  }
  if (kept.dropped) return
  kept.drawn = true
  // Its draw set the card's title: the page's own, and the shown page's again while that one stays.
  kept.title = document.title
  if (context.arg === arg) present(kept, kept.landing === undefined ? undefined : { arg, at: kept.landing })
  else if (current?.title !== undefined) document.title = current.title
  // A page drawn again takes the old one's place, unless the old one shows: the card came back to it meanwhile.
  for (const other of pages) if (other !== kept && other !== current && other.page.arg === arg) drop(other)
}

function moved(arg: string, at?: string) {
  // As the page leaves it, unless a page being drawn may have set it already.
  if (current && pages.every((page) => page.drawn)) current.title = document.title
  if (current?.page.arg === arg) {
    if (current.title !== undefined) document.title = current.title
    return current.places.forEach((fn) => fn({ arg, at }))
  }
  const kept = pages.find((page) => page.page.arg === arg)
  if (!kept) void fill(arg, at)
  else if (kept.drawn) present(kept, { arg, at })
  else kept.landing = at
}

function present(kept: Kept, again?: { arg: string; at?: string }) {
  const old = current
  if (old) {
    old.page.element.inert = true
    // Its sound stops with it.
    old.page.element.querySelectorAll<HTMLMediaElement>("audio, video").forEach((media) => media.pause())
    // Left with unsaved edits, which the user chose to discard.
    if (dirty) drop(old)
  }
  current = kept
  kept.page.element.inert = false
  pages = [...pages.filter((page) => page !== kept), kept]
  if (kept.title !== undefined) document.title = kept.title
  if (!kept.shownOnce) {
    kept.shownOnce = true
    for (const [id, value] of Object.entries(context.controls)) kept.controls.set(id, { value, ...kept.controls.get(id) })
  }
  // Only what differs from the page before, or from what the app's header was told.
  for (const [id, change] of kept.controls) {
    if (!same(change, old?.controls.get(id)) || news(id, change)) controls.set(id, change)
  }
  for (const fn of kept.due) fn()
  kept.due.clear()
  if (again) kept.places.forEach((fn) => fn(again))
  const drawn = pages.filter((page) => page.drawn)
  for (const page of drawn.slice(0, Math.max(0, drawn.length - 5))) drop(page)
  // A page takes the keyboard on its window's focus, which it had.
  if (document.hasFocus()) dispatchEvent(new Event("focus"))
}

/** ⌘← and ⌘→ go Back and Forward, as ⌘[ and ⌘] do (the app's), unless a text field has the keyboard: there they move
 *  its caret. In the capture phase, before a page's own keys (a tree's ← goes to the parent row). */
function backForward(event: KeyboardEvent) {
  const back = event.key === "ArrowLeft"
  if (!back && event.key !== "ArrowRight") return
  if (!event.metaKey || event.shiftKey || event.altKey || event.ctrlKey) return
  const target = event.composedPath()[0]
  if (target instanceof HTMLElement && (target.isContentEditable || target.matches("input, textarea"))) return
  event.preventDefault()
  event.stopPropagation()
  tell("card.step", { back })
}

/** One watch of the machine per path for all pages: on a remote machine each one polls. */
const watched = new Map<string, { fns: Set<() => void>; off: Off }>()
function watch(path: string, fn: () => void): Off {
  let shared = watched.get(path)
  if (!shared) {
    const fns = new Set<() => void>()
    shared = { fns, off: oriel.files.watch(path, () => [...fns].forEach((each) => each())) }
    watched.set(path, shared)
  }
  const { fns, off } = shared
  fns.add(fn)
  return () => {
    if (!fns.delete(fn) || fns.size) return
    watched.delete(path)
    off()
  }
}

function drop(kept: Kept) {
  if (kept.dropped) return
  kept.dropped = true
  for (const off of kept.offs.splice(0)) {
    try {
      off()
    } catch (error) {
      console.error(error)
    }
  }
  kept.page.element.remove()
  pages = pages.filter((page) => page !== kept)
  if (current === kept) current = undefined
}

// Console lines and uncaught errors go to the plugin's log too (~/Library/Logs/Oriel/plugins/<id>.log), where its
// author and their agents read them.
const text = (value: unknown) => {
  if (typeof value === "string") return value
  if (value instanceof Error) return `${value.message}${value.stack ? `\n${value.stack.split("\n")[0]}` : ""}`
  try {
    return JSON.stringify(value) ?? String(value)
  } catch {
    return String(value)
  }
}
for (const level of ["log", "info", "warn", "error", "debug"] as const) {
  const original = console[level].bind(console)
  console[level] = (...values: unknown[]) => {
    original(...values)
    void call("console", { level, text: values.map(text).join(" ") }).catch(() => {})
  }
}
addEventListener("error", (event) => console.error(event.error ?? event.message))
addEventListener("unhandledrejection", (event) => console.error(event.reason))

// The app alone gives a card the keyboard. WebKit makes the web view the window's first responder on any `focus()` while
// its page has none, which would take the keyboard from the pane in use (a tree that puts back its focused row after a
// refresh). A page takes the keyboard on its window's `focus` event.
const focus = HTMLElement.prototype.focus
/** A press in the page, until its event ends: it can reach the page before WebKit marks the page focused. */
let pressed = false
addEventListener("pointerdown", () => {
  pressed = true
  setTimeout(() => (pressed = false))
}, true)
HTMLElement.prototype.focus = function (options) {
  if (context.keyboard || pressed || document.hasFocus()) focus.call(this, options)
}

// The card is ready when `main` returns or calls `card.ready()`; an error from it shows in the card.
try {
  // Not a literal: the build leaves it to the page, which loads the plugin's own file.
  const entry = `./${context.entry}`
  const { default: main } = await import(entry)
  await main(oriel)
  card.ready()
} catch (error) {
  const failure = error as Error
  tell("card.failed", { text: String(failure?.message ?? failure), stack: String(failure?.stack ?? "").split("\n")[0] })
}
