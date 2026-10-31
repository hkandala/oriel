// Git: a repository's home and its diffs, places of one card (ui/plugins#git). The home is `<root>/`, a diff
// `<root>/ <source>`; the card moves between them with `card.go` and the app's Back and Forward. The diff, with
// @pierre/diffs, loads on its first use.
import type { Oriel } from "@oriel/plugin-api"
import "./rows.css"
import "./home.css"
import "./diff.css"
import { bind, control, home, parse } from "./lib"

/** Each place's own header controls; the spacer is both's. */
const HOME = ["git.branch", "git.fetch", "git.pull", "git.push"]
const DIFF = ["diff.home", "diff.layout", "diff.file-list", "diff.previous", "diff.next"]

export default async function main(oriel: Oriel) {
  bind(oriel)
  // The SF Symbols the rows draw, as masks in the text's color.
  const names = ["doc", "plus", "minus", "arrow.triangle.branch", "cloud", "tag"]
  const urls = await Promise.all(names.map((name) => oriel.symbol(name, 12)))
  const sheet = document.createElement("style")
  sheet.textContent = `:root { ${names.map((name, index) => `--sf-${name.replaceAll(".", "-")}: url(${urls[index]});`).join(" ")} }`
  document.head.append(sheet)
  // After `bind`: the home reads the card's state as it loads.
  const Home = await import("./home")
  let Diff: typeof import("./diff") | undefined
  let place = parse(oriel.card.arg)
  let watched = ""
  let off: (() => void) | undefined

  /** Shows a place: its header controls, then its page. */
  async function show(arg: string, at?: string) {
    const shown = (place = parse(arg))
    const diff = shown.source !== undefined
    for (const id of HOME) control(id, { hidden: diff })
    for (const id of DIFF) control(id, { hidden: !diff })
    watch(shown.root)
    if (!diff) {
      Diff?.hide()
      return Home.show(shown.root, at)
    }
    Home.hide()
    Diff ??= await import("./diff")
    // Not after another move meanwhile.
    if (place === shown) await Diff.show(shown.root, shown.source!, at)
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

  oriel.on("place", ({ arg, at }) => void show(arg, at))
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
  await show(oriel.card.arg, oriel.card.at)
}
