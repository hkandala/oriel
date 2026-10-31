// Calls every part of the plugin API on the card's folder, one line each: "<part>: <what came back>". A UI test
// (PluginAPITests) reads the lines and checks the folder through herdr. Plain JavaScript: no build needed.

/** @param {import("@oriel/plugin-api").Oriel} oriel */
export default async function main(oriel) {
  if (oriel.card.arg.endsWith("/fail/")) throw new Error("asked to fail")
  const root = oriel.card.arg.replace(/\/$/, "")
  const list = document.body.appendChild(document.createElement("div"))
  const line = (part, text) => {
    const item = document.getElementById(part) ?? list.appendChild(document.createElement("div"))
    item.id = part
    item.textContent = `${part}: ${text}`
  }
  const check = async (part, fn) => {
    try {
      line(part, await fn())
    } catch (error) {
      line(part, `${error.code} ${error.message}`)
    }
  }
  const button = (title, fn) => {
    const node = document.body.appendChild(document.createElement("button"))
    node.textContent = title
    node.onclick = fn
  }

  const runs = (oriel.state.get()?.runs ?? 0) + 1
  oriel.state.set({ runs })
  line("state", runs)
  line("card", `${oriel.api} ${oriel.card.plugin.id} ${oriel.card.machine.name} ${oriel.card.arg}`)
  line("theme", `${oriel.theme.dark ? "dark" : "light"} ${oriel.theme.textSize > 0}`)

  await check("files.write", async () => (await oriel.files.write(`${root}/a.txt`, "hello\n")).hash.length > 0)
  const read = await oriel.files.read(`${root}/a.txt`)
  line("files.read", JSON.stringify(read.text))
  await check("files.readBytes", async () => (await oriel.files.readBytes(`${root}/a.txt`)).data.length)
  await check("files.info", async () => {
    const info = await oriel.files.info(`${root}/a.txt`)
    return `${info.size} ${info.folder} ${info.icon.startsWith("data:image/png;base64,i")}`
  })
  await oriel.files.write(`${root}/a.txt`, "two\n")
  await check("files.changed", () => oriel.files.write(`${root}/a.txt`, "three\n", { over: read.hash }))
  await check("files.missing", () => oriel.files.read(`${root}/none.txt`))

  const git = (...argv) => oriel.run(["git", ...argv])
  await check("run", async () => {
    const result = await oriel.run(["sh", "-c", "pwd; cat; exit 3"], { cwd: root, stdin: "in" })
    return `${result.code} ${JSON.stringify(result.stdout)}`
  })
  await git("init", "-q", "-b", "main", root)
  await oriel.run(["git", "config", "user.email", "t@t"], { cwd: root })
  await oriel.run(["git", "config", "user.name", "t"], { cwd: root })
  await oriel.files.write(`${root}/.gitignore`, "ignored.txt\n")
  await oriel.files.write(`${root}/ignored.txt`, "x\n")
  // Folders first; git's ignored files marked.
  await check("files.list", async () =>
    (await oriel.files.list(root)).map((entry) => entry.name + (entry.folder ? "/" : "") + (entry.ignored ? "!" : "")).join(" "))
  await check("files.paths", async () => (await oriel.files.paths(root)).sort().join(" "))
  await check("git.root", () => oriel.git.root(root))
  await check("git.status", async () => (await oriel.git.status(root)).map((c) => `${c.letter} ${c.path}`).join(", "))
  await oriel.git.stage(root, ["a.txt"])
  await check("git.changes", async () => (await oriel.git.changes(root)).staged.map((c) => c.path).join(", "))
  await check("git.commit", async () => {
    await oriel.git.commit(root, "one")
    return (await oriel.git.log(root, { limit: 5 })).map((c) => c.subject).join(", ")
  })
  await check("git.head", async () => (await oriel.git.head(root))?.branch)
  await check("git.branches", async () => (await oriel.git.branches(root)).map((b) => b.name).join(", "))
  await oriel.files.write(`${root}/a.txt`, "four\n")
  await check("git.diff", async () => (await oriel.git.diff(root, "uncommitted")).includes("+four"))
  await oriel.git.unstage(root)

  await check("clipboard", async () => (await oriel.clipboard.write("oriel-plugin-api"), "written"))
  await check("symbol", async () => (await oriel.symbol("star", 12)).startsWith("data:image/png;base64,"))
  oriel.controls.set("count", { value: "counted" })
  line("controls", oriel.controls.get("count"))

  // The watch called right after the card came into view again: no file change does that.
  let watched = 0, shown = 0, hidden = false, again = false
  oriel.files.watch(`${root}/watched.txt`, () => {
    line("watch", ++watched)
    if (again) line("watch.again", "yes")
    again = false
  })
  oriel.on("control", ({ id }) => line("control", id))
  oriel.on("place", ({ arg, at }) => line("place", `${arg} ${at ?? ""}`))
  oriel.on("save", () => line("save", "heard"))
  oriel.on("keyboard", (yes) => line("keyboard", yes))
  oriel.on("visible", (yes) => {
    line("visible", `${yes} ${++shown}`)
    again = yes && hidden
    hidden = !yes
  })
  oriel.on("theme", (theme) => line("theme", `${theme.dark ? "dark" : "light"} changed`))

  button("Toast", async () => line("toast", await oriel.toast("Pick one", ["No", "Yes"])))
  button("Menu", async () => line("menu", await oriel.menu.show([{ title: "Heading" }, { value: "one", title: "One" }, "-",
    { value: "two", title: "Two", symbol: "star" }])))
  button("Go", () => oriel.card.go(`${root}/sub/`, { at: "x" }))
  button("Dirty", () => oriel.card.setDirty(true))
  button("Clean", () => oriel.card.setDirty(false))
  button("Open", () => oriel.open(`${root}/a.txt`, { how: "tab" }))
  button("Pick", async () => line("pick", await oriel.pick.folder(root)))
  line("ready", "yes")
}
