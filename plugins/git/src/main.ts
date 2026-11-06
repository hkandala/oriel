// Git: a repository's home and its diffs, places of one card (plugins/default-plugins#git), each in a page the card
// keeps (`ovvi.pages`). The home is `<root>/`, a diff `<root>/ <source>`; the card moves between them with `card.go` and
// the app's Back and Forward. The home is in the entry, so it opens at once; the diff, with @pierre/diffs, loads on its
// first use.
import type { Ovvi } from "@ovvi/plugin-api"
import "./rows.css"
import "./home.css"
import "./diff.css"
import * as Home from "./home"
import { bind, parse } from "./lib"

/** Each place's own header controls; the spacer is both's. */
const HOME = ["git.branch", "git.working", "git.fetch", "git.pull", "git.push"]
const DIFF = ["diff.home", "diff.layout", "diff.wrap", "diff.file-list", "diff.previous", "diff.next"]

export default async function main(ovvi: Ovvi) {
  bind(ovvi)
  // The SF Symbols the rows draw, as masks in the text's color. While the app draws them, the first place reads and
  // draws under the card's loader, which goes once both are done (`main` returns). One the app lacks draws nothing.
  // The placeholders' at their size.
  const big = ["checkmark.circle", "folder.badge.questionmark", "magnifyingglass"]
  const names = ["plus", "arrow.uturn.backward", "minus", "source.branch", "cloud", "tag", "xmark", ...big]
  const symbols = Promise.all(names.map((name) => ovvi.symbol(name, big.includes(name) ? 30 : 12).catch(() => "")))
  .then((urls) => {
    const sheet = document.createElement("style")
    sheet.textContent = `:root { ${names.map((name, index) => `--sf-${name.replaceAll(".", "-")}: url(${urls[index]});`).join(" ")} }`
    document.head.append(sheet)
  })
  // Each place in a page of its own, which the card keeps: Back and Forward show it as it was.
  const pages = ovvi.pages.route(async (page) => {
    const { root, source } = parse(page.arg)
    for (const id of HOME) page.ovvi.controls.set(id, { hidden: source !== undefined })
    for (const id of DIFF) page.ovvi.controls.set(id, { hidden: source === undefined })
    if (source === undefined) await Home.make(page, root)
    else await (await import("./diff")).make(page, root, source)
  })
  await Promise.all([pages, symbols])
}
