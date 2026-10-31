// A plugin's entry: the app calls its default export with the `oriel` object (the plugin API's types come from
// @oriel/plugin-api, which Oriel writes into its plugins folder). This one shows a text file and its line count, and
// follows the file as it changes.
import type { Oriel } from "@oriel/plugin-api"
import "./main.css"

export default async function main(oriel: Oriel) {
  const pre = document.body.appendChild(document.createElement("pre"))

  async function load() {
    try {
      const { text } = await oriel.files.read(oriel.card.arg)
      // Text from a file goes in as text, never as HTML.
      pre.textContent = text
      oriel.controls.set("lines", { value: `${text.split("\n").length} lines` })
    } catch (error) {
      pre.textContent = ""
      oriel.controls.set("lines", { value: (error as Error).message })
    }
  }

  oriel.files.watch(oriel.card.arg, load)
  await load()
}
