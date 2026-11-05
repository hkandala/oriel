// The tree's Git status bar (files.ts), only while its root is in a repository: the branch, the count of changes,
// how far the branch is ahead of and behind its upstream, and a button that opens Git on the repository.
import type { Ovvi } from "@ovvi/plugin-api"
import { symbols } from "./place"

type Head = { branch: string; ahead: number; behind: number } | null

/** Fills `bar`; the update it returns shows the repository's state, or hides the bar (no repository). */
export function footer(ovvi: Ovvi, bar: HTMLElement) {
  bar.innerHTML = `<span class="branch"></span><span class="changes"></span><span class="sync"></span><button
    aria-label="Open in Git" title="Open in Git"></button>`
  const [branch, changes, sync] = bar.querySelectorAll("span")
  const button = bar.querySelector("button")!
  let repo: string | null = null
  // Git's home on the repository, in a new tab at the end.
  button.onclick = () => repo && void ovvi.open(`${repo}/`, { plugin: "git", how: "tab" }).catch(console.error)
  symbols(ovvi, ["source.branch"], 14)
  button.style.setProperty("--symbol", "var(--sf-source-branch)")
  return (root: string | null, count: number, head: Head) => {
    repo = root
    bar.hidden = !root || !head
    if (!head) return
    branch.textContent = head.branch
    changes.textContent = count ? `${count} ${count === 1 ? "change" : "changes"}` : ""
    sync.textContent = [head.ahead ? `↑${head.ahead}` : "", head.behind ? `↓${head.behind}` : ""].join(" ").trim()
  }
}
