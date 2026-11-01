// Git: a repository's home and its diffs, places of one card (plugins/default-plugins#git). The home is `<root>/`, a diff
// `<root>/ <source>`; the card moves between them with `card.go` and the app's Back and Forward. The home is in the
// entry, so it opens at once; the diff, with @pierre/diffs, loads on its first use.
import type { Oriel } from "@oriel/plugin-api"
import "./rows.css"
import "./home.css"
import "./diff.css"
import * as Home from "./home"
import { bind, control, home, parse } from "./lib"

/** Each place's own header controls; the spacer is both's. */
const HOME = ["git.branch", "git.fetch", "git.pull", "git.push"]
const DIFF = ["diff.home", "diff.layout", "diff.file-list", "diff.previous", "diff.next"]

export default async function main(oriel: Oriel) {
  bind(oriel)
  // The SF Symbols the rows draw, as masks in the text's color. While the app draws them, the first place reads and
  // draws under the card's loader, which goes once both are done (`main` returns). One the app lacks draws nothing.
  // The placeholders' at their size.
  const big = ["checkmark.circle", "folder.badge.questionmark"]
  const names = ["doc", "plus", "minus", "source.branch", "cloud", "tag", ...big]
  const symbols = Promise.all(names.map((name) => oriel.symbol(name, big.includes(name) ? 30 : 12).catch(() => "")))
  .then((urls) => {
    const sheet = document.createElement("style")
    sheet.textContent = `:root { ${names.map((name, index) => `--sf-${name.replaceAll(".", "-")}: url(${urls[index]});`).join(" ")} }`
    document.head.append(sheet)
  })
  let Diff: typeof import("./diff") | undefined
  let place = parse(oriel.card.arg)
  let watched = ""
  let off: (() => void) | undefined

  /** Shows a place's page and its header controls. A diff draws first, then takes the home's place. */
  async function show(arg: string, at?: string) {
    const shown = (place = parse(arg))
    const controls = (diff: boolean) => {
      for (const id of HOME) control(id, { hidden: diff })
      for (const id of DIFF) control(id, { hidden: !diff })
    }
    watch(shown.root)
    if (shown.source === undefined) {
      controls(false)
      Diff?.hide()
      return Home.show(shown.root, at)
    }
    Diff ??= await import("./diff")
    // Not after another move meanwhile.
    if (place !== shown || !(await Diff.show(shown.root, shown.source, at)) || place !== shown) return
    controls(true)
    Home.hide()
  }

  /** While the card shows: the home reads again after each change under the root, Uncommitted asks for its patch
   *  again, and a diff whose first read failed tries again. */
  function watch(root: string) {
    if (root === watched) return
    off?.()
    watched = root
    off = oriel.files.watch(root, () => {
      if (place.source === undefined) void Home.load()
      else if (place.source === "uncommitted" || Diff?.failed()) void Diff?.refresh()
    })
  }

  oriel.on("place", ({ arg, at }) => void show(arg, at).catch(console.error))
  oriel.on("control", ({ id, value }) => {
    switch (id) {
      case "diff.home": return oriel.card.go(home(place.root))
      case "diff.layout": return Diff?.layout(value === "split")
      case "diff.file-list": return Diff?.toggleList()
      case "diff.previous": return Diff?.step(-1)
      case "diff.next": return Diff?.step(1)
      default: Home.pick(id, value as string | undefined)
    }
  })
  await Promise.all([show(oriel.card.arg, oriel.card.at), symbols])
}
