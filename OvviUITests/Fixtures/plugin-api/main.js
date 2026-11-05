// Calls every part of the plugin API on the card's folder, one line each: "<part>: <what came back>". A UI test
// (PluginAPITests) reads the lines and checks the folder through herdr. Plain JavaScript: no build needed.

/** @param {import("@ovvi/plugin-api").Ovvi} ovvi */
export default async function main(ovvi) {
  if (ovvi.card.arg.endsWith("/fail/")) throw new Error("asked to fail")
  const root = ovvi.card.arg.replace(/\/$/, "")
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

  const runs = (ovvi.state.get()?.runs ?? 0) + 1
  ovvi.state.set({ runs })
  line("state", runs)
  line("card", `${ovvi.api} ${ovvi.card.plugin.id} ${ovvi.card.machine.name} ${ovvi.card.arg}`)
  line("theme", `${ovvi.theme.dark ? "dark" : "light"} ${ovvi.theme.textSize > 0}`)

  await check("files.write", async () => (await ovvi.files.write(`${root}/a.txt`, "hello\n")).hash.length > 0)
  const read = await ovvi.files.read(`${root}/a.txt`)
  line("files.read", JSON.stringify(read.text))
  await check("files.readBytes", async () => (await ovvi.files.readBytes(`${root}/a.txt`)).data.length)
  await check("files.info", async () => {
    const info = await ovvi.files.info(`${root}/a.txt`)
    return `${info.size} ${info.folder} ${info.icon.startsWith("data:image/png;base64,i")}`
  })
  await ovvi.files.write(`${root}/a.txt`, "two\n")
  await check("files.changed", () => ovvi.files.write(`${root}/a.txt`, "three\n", { over: read.hash }))
  await check("files.missing", () => ovvi.files.read(`${root}/none.txt`))

  const git = (...argv) => ovvi.run(["git", ...argv])
  await check("run", async () => {
    const result = await ovvi.run(["sh", "-c", "pwd; cat; exit 3"], { cwd: root, stdin: "in" })
    return `${result.code} ${JSON.stringify(result.stdout)}`
  })
  await git("init", "-q", "-b", "main", root)
  await ovvi.run(["git", "config", "user.email", "t@t"], { cwd: root })
  await ovvi.run(["git", "config", "user.name", "t"], { cwd: root })
  await ovvi.files.write(`${root}/.gitignore`, "ignored.txt\n")
  await ovvi.files.write(`${root}/ignored.txt`, "x\n")
  // Folders first; git's ignored files marked.
  await check("files.list", async () =>
    (await ovvi.files.list(root)).map((entry) => entry.name + (entry.folder ? "/" : "") + (entry.ignored ? "!" : "")).join(" "))
  await check("files.paths", async () => (await ovvi.files.paths(root)).sort().join(" "))
  await check("git.root", () => ovvi.git.root(root))
  await check("git.status", async () => (await ovvi.git.status(root)).map((c) => `${c.letter} ${c.path}`).join(", "))
  await ovvi.git.stage(root, ["a.txt"])
  await check("git.changes", async () => (await ovvi.git.changes(root)).staged.map((c) => c.path).join(", "))
  await check("git.commit", async () => {
    await ovvi.git.commit(root, "one")
    return (await ovvi.git.log(root, { limit: 5 })).map((c) => c.subject).join(", ")
  })
  await check("git.head", async () => (await ovvi.git.head(root))?.branch)
  await check("git.branches", async () => (await ovvi.git.branches(root)).map((b) => b.name).join(", "))
  await ovvi.files.write(`${root}/a.txt`, "four\n")
  await check("git.diff", async () => (await ovvi.git.diff(root, "uncommitted")).includes("+four"))
  await ovvi.git.unstage(root)

  await check("clipboard", async () => (await ovvi.clipboard.write("ovvi-plugin-api"), "written"))
  await check("symbol", async () => (await ovvi.symbol("star", 12)).startsWith("data:image/png;base64,"))
  ovvi.controls.set("count", { value: "counted" })
  line("controls", ovvi.controls.get("count"))

  // The watch called right after the card came into view again: no file change does that.
  let watched = 0, shown = 0, hidden = false, again = false
  ovvi.files.watch(`${root}/watched.txt`, () => {
    line("watch", ++watched)
    if (again) line("watch.again", "yes")
    again = false
  })
  ovvi.on("control", ({ id }) => line("control", id))
  ovvi.on("place", ({ arg, at }) => line("place", `${arg} ${at ?? ""}`))
  ovvi.on("save", () => line("save", "heard"))
  ovvi.on("keyboard", (yes) => line("keyboard", yes))
  ovvi.on("visible", (yes) => {
    line("visible", `${yes} ${++shown}`)
    again = yes && hidden
    hidden = !yes
  })
  ovvi.on("theme", (theme) => line("theme", `${theme.dark ? "dark" : "light"} changed`))

  button("Toast", async () => line("toast", await ovvi.toast("Pick one", ["No", "Yes"])))
  button("Menu", async () => line("menu", await ovvi.menu.show([{ title: "Heading" }, { value: "one", title: "One" }, "-",
    { value: "two", title: "Two", symbol: "star" }])))
  button("Go", () => ovvi.card.go(`${root}/sub/`, { at: "x" }))
  button("Dirty", () => ovvi.card.setDirty(true))
  button("Clean", () => ovvi.card.setDirty(false))
  button("Open", () => ovvi.open(`${root}/a.txt`, { how: "tab" }))
  button("Pick", async () => line("pick", await ovvi.pick.folder(root)))
  line("ready", "yes")
}
