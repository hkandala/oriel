// A plugin's entry: the app calls its default export with the `ovvi` object (the plugin API's types come from
// @ovvi/plugin-api, which Ovvi writes into its plugins folder). This one shows a text file and its line count, and
// follows the file as it changes. Its one setting, on its page in Settings, wraps long lines.
import type { Ovvi } from "@ovvi/plugin-api"
import "./main.css"

export default async function main(ovvi: Ovvi) {
  const pre = document.body.appendChild(document.createElement("pre"))
  const wrap = (yes: boolean) => (pre.style.whiteSpace = yes ? "pre-wrap" : "pre")
  wrap(ovvi.settings.get<boolean>("wrap"))
  ovvi.on("settings", (changed) => "wrap" in changed && wrap(changed.wrap === true))

  async function load() {
    try {
      const { text } = await ovvi.files.read(ovvi.card.arg)
      // Text from a file goes in as text, never as HTML.
      pre.textContent = text
      ovvi.controls.set("lines", { value: `${text.split("\n").length} lines` })
    } catch (error) {
      pre.textContent = ""
      ovvi.controls.set("lines", { value: (error as Error).message })
    }
  }

  ovvi.files.watch(ovvi.card.arg, load)
  await load()
}
