// The tree's status bar (files.ts), under the tree in every folder: the machine on a remote one, the root's folders
// and files (and the hidden ones while they hide); in a repository, at the right, the branch, the lines added and
// removed, Pull and Push while there is something to pull or push, Fetch, and Git, which opens Git's home on it.
import type { Ovvi } from "@ovvi/plugin-api"
import { how, symbols } from "./place"

type Head = { branch: string; ahead: number; behind: number } | null

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`

/** Fills `bar`. `folder` shows the root's counts; `repo` the repository's part, or none outside one. `again` reads the
 *  repository anew after a write. */
export function footer(ovvi: Ovvi, bar: HTMLElement, again: () => void) {
  const machine = ovvi.card.machine
  bar.innerHTML = `<span class="machine" hidden></span><span class="folder"></span><span class="git" hidden><span
    class="branch"></span><span class="added"></span><span class="removed"></span><button class="pull"></button><button
    class="push"></button><button class="fetch" title="Fetch" aria-label="Fetch"></button><span class="rule"></span><button
    class="open" title="Open in Git" aria-label="Open in Git">Git</button></span>`
  const [where, folder, git, branch, added, removed] = bar.querySelectorAll("span")
  const [pull, push, fetch, open] = bar.querySelectorAll("button")
  symbols(ovvi, ["server.rack", "folder", "source.branch", "arrow.down", "arrow.up", "arrow.clockwise",
    "arrow.up.right.square"], 11)
  where.hidden = !machine.remote
  where.textContent = machine.name
  let repo: string | null = null
  // Git's home on the repository: a new tab beside, selected; ⌘ in the background, ⌥ to the side.
  open.onclick = (event) => {
    const to = how(event)
    if (repo) {
      void ovvi.open(`${repo}/`, { plugin: "git", how: to === "card" ? "tab" : to, background: to !== "card" })
        .catch(console.error)
    }
  }
  /** One write at a time, every button off meanwhile and a spinner on its own; git's message in a toast. */
  const write = (button: HTMLButtonElement, done: (root: string) => Promise<void>) => async () => {
    if (!repo) return
    button.toggleAttribute("data-busy", true)
    for (const each of [pull, push, fetch]) each.disabled = true
    await done(repo).catch((error) => void ovvi.toast(String((error as Error).message ?? error)))
    button.toggleAttribute("data-busy", false)
    for (const each of [pull, push, fetch]) each.disabled = false
    again()
  }
  pull.onclick = write(pull, (root) => ovvi.git.pull(root))
  push.onclick = write(push, (root) => ovvi.git.push(root))
  fetch.onclick = write(fetch, (root) => ovvi.git.fetch(root))
  return {
    folder(folders: number, files: number, hidden: number) {
      folder.textContent = `${plural(folders, "folder")}, ${plural(files, "file")}${hidden ? ` · ${hidden} hidden` : ""}`
    },
    repo(root: string | null, head: Head, lines: { added: number; removed: number }) {
      repo = root
      git.hidden = !root || !head
      if (!head) return
      branch.textContent = head.branch
      added.textContent = lines.added ? `+${lines.added}` : ""
      removed.textContent = lines.removed ? `−${lines.removed}` : ""
      for (const [button, count, word] of [[pull, head.behind, "Pull"], [push, head.ahead, "Push"]] as const) {
        button.hidden = !count
        button.textContent = String(count)
        button.title = `${word}, ${count} ${word === "Pull" ? "behind" : "ahead"}`
        button.ariaLabel = button.title
      }
    },
  }
}
