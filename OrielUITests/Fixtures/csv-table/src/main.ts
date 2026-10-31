// The building page's CSV Table (plugins/building), the fixture of PackageTests. The test edits the
// caption below and presses Reload Plugin.
import type { Oriel } from "@oriel/plugin-api"
import { parse } from "./parse"
import "./table.css"

type State = { column?: number; descending?: boolean; scroll?: number }

const caption = "CSV Table one"

export default async function main(oriel: Oriel) {
  const path = oriel.card.arg
  let state = oriel.state.get<State>() ?? {}
  let rows: string[][] = []
  const title = document.body.appendChild(document.createElement("p"))
  title.textContent = caption
  const table = document.body.appendChild(document.createElement("table"))

  function save(change: State) {
    state = { ...state, ...change }
    oriel.state.set(state)
  }

  function draw() {
    const header = oriel.controls.get("first-row") === true
    const [head, ...body] = header ? rows : [rows[0]?.map((_, i) => `${i + 1}`) ?? [], ...rows]
    const { column, descending } = state
    if (column !== undefined) {
      body.sort((a, b) => (a[column] ?? "").localeCompare(b[column] ?? "", undefined, { numeric: true }))
      if (descending) body.reverse()
    }
    table.replaceChildren()
    const tr = table.createTHead().insertRow()
    head.forEach((title, i) => {
      const th = tr.appendChild(document.createElement("th"))
      th.textContent = title + (i === column ? (descending ? " ↓" : " ↑") : "")
      th.onclick = () => {
        save({ column: i, descending: i === column && !descending })
        draw()
      }
    })
    const tbody = table.createTBody()
    for (const row of body) {
      const line = tbody.insertRow()
      for (const cell of row) line.insertCell().textContent = cell
    }
    oriel.controls.set("rows", { value: `${body.length} rows` })
  }

  async function load() {
    try {
      const { text } = await oriel.files.read(path)
      rows = parse(text, path.endsWith(".tsv") ? "\t" : ",")
      draw()
    } catch (error) {
      table.replaceChildren()
      oriel.controls.set("rows", { value: (error as Error).message })
    }
  }

  oriel.on("control", ({ id }) => {
    if (id === "reload") load()
    if (id === "first-row") draw()
  })
  oriel.files.watch(path, load)
  addEventListener("scroll", () => save({ scroll: scrollY }), { passive: true })

  await load()
  scrollTo(0, state.scroll ?? 0)
}
