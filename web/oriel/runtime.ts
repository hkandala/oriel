// The runtime: the `oriel` object of a plugin's page (oriel.d.ts), made from the card's context the app puts in the
// page at document start, before the plugin's code runs. Its messages are the app's own (Oriel/Plugins/Bridge.swift):
// `{ call, args }` to the app, answered with JSON or rejected with "<code>: <text>"; `oriel_receive(name, data)` from
// it.
import type { Card, Controls, MenuItem, Oriel, OrielError, RunResult, Theme } from "./oriel"

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
      if ("value" in data) context.controls[data.id] = data.value
      break
    case "place":
      context.arg = data.arg
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
  setDirty: (dirty) => tell("card.setDirty", { dirty }),
}

const controls: Controls = {
  get: (id) => context.controls[id],
  set(id, change) {
    if (change.value !== undefined) context.controls[id] = change.value
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
    stage: (root, paths) => call("git.stage", { root, paths }),
    unstage: (root, paths) => call("git.unstage", { root, paths }),
    commit: (root, message) => call("git.commit", { root, message }),
    fetch: (root) => call("git.fetch", { root }),
    pull: (root) => call("git.pull", { root }),
    push: (root) => call("git.push", { root }),
    switch: (root, branch) => call("git.switch", { root, branch }),
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
  toast(text, buttons) {
    const id = ++next
    return new Promise((resolve) => {
      toasts.set(id, resolve)
      tell("toast", { id, text, buttons })
    })
  },
  symbol: (name, size) => call("symbol", { name, size }),
  on(event: string, fn: Handler) {
    const set = handlers.get(event) ?? new Set()
    handlers.set(event, set.add(fn))
    return () => void set.delete(fn)
  },
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
