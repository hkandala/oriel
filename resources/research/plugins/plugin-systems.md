# Plugin systems: what Oriel borrows

Context: an Oriel plugin is a folder with a manifest and `main.ts`. The app bundles it with esbuild, serves it into one WKWebView per card, and the plugin calls native Swift through a typed `oriel` module. Hot reload runs on file change, and the built-ins use the same format. For each system below: how it works, then what to take and what to skip.

---

## 1. bb (get-bb/bb): "the agent IDE that builds itself"

**Which bb.** Three things share the name. One is get-bb/bb (getbb.app): an MIT-licensed agentic IDE (desktop, web, CLI and HTTP API) that runs Claude Code, Codex, pi and other agents. Another is shuyhere/bb-agent, a small terminal agent. The third is Bitbucket, which has no "bb IDE". I chose **get-bb/bb**. It is the AI/agent IDE, it has a real plugin SDK, and it ships 21 bundled plugins built on that same SDK (git, GitHub, monaco-editor, pdf-preview, theme-preview). It is the closest match to Oriel. https://github.com/get-bb/bb · https://getbb.app · https://github.com/MGrin/awesome-bb-plugins

**Written/loaded.** A plugin is an npm-style package. `bb.server` is the backend factory, run by the daemon. `bb.app` is an optional React frontend that runs inside the bb UI. `bb.host` is an optional full-trust Node entry. Path installs load the server `.ts` directly. `bb plugin build` uses a pinned esbuild and Tailwind to make `dist/app.js` and `dist/server.js`. React and the SDK are not bundled: they are "shimmed" to the host's own runtime.

**Manifest** (real: `plugins/pdf-preview/package.json`):
```json
{
  "name": "bb-plugin-pdf-preview", "version": "0.1.0", "type": "module",
  "engines": { "bb": ">=0.0", "bbPluginSdk": ">=0.4.84" },
  "bb": {
    "name": "PDF preview",
    "description": "Preview PDF files with the browser's built-in viewer.",
    "branding": { "icon": "FileText" },
    "server": "./server.ts",
    "app": "./app.tsx"
  }
}
```

**API shape.**
```ts
// server.ts
export default async function plugin(bb: BbPluginApi) { /* bb.settings, storage, rpc, cli, events.on, onDispose … */ }
// app.tsx: a file opener, which is their version of our "card for a file type"
export default definePluginApp((app) => {
  app.slots.fileOpener({ id: "pdf", title: "PDF viewer", extensions: ["pdf"], component: PdfFileOpener });
});
function PdfFileOpener({ path, source, Original }: PluginFileOpenerProps) { /* return <Original/> to defer to the built-in */ }
// header button: an action with a placement
app.slots.experimental_threadAction({ id: "deploy", title: "Deploy", icon: "Rocket", placement: "header",
  useData: ({ threadIds }) => useDeployable(threadIds),
  item: ({ thread, data }) => data.has(thread.id) ? { label: "Deploy", run: () => … } : null });
```

**Hot reload.** `bb plugin dev`: you save, it rebuilds, it reloads. Open pages pick up the new UI live. A failed build skips that cycle and the watcher keeps running. The reload works in **generations**. bb first runs the new factory against a *candidate* registration set. If the candidate throws, the old set stays live. If it succeeds, the old generation is torn down: sockets close, signals abort, dispose hooks run LIFO, and in-flight handlers get 5 s to finish. A stale `bb` object then throws `PluginContextStaleError` when used.

**Security.** None at runtime, and the docs say so: frontend content scripts are "full-trust, same-origin page code — **not a security sandbox**". The only hardening is at build and install time. Git installs run with `--ignore-scripts`. SVG icons pass a validator and get a `default-src 'none'` CSP. Built artifacts carry `sdkMajor`, and an artifact built for a different SDK major is refused.

**Versioning.** Every new public API starts with an `experimental_` prefix and an entry in `docs/api_to_audit.md`. Aliases warn for one release and then expire. `engines.bbPluginSdk` is a semver range. Managed installs refuse a plugin pinned to a different SDK major.

**Take**
- **Generation-based reload with a candidate check.** Run the new bundle first and swap only if it loads. Keep the old card alive on a build or init error and show the error as a toast. This is the right behaviour for our hot reload of `main.ts`.
- **`Original` fallback in file openers.** A plugin that claims `*.md` can hand the card back to the built-in. That is cheap to add and lets built-ins and plugins overlap safely.
- **"Forkable built-ins"** (`docs/forkable-plugins.md`): a lint rule plus a CI job check that each built-in builds with only the public SDK. This matches our AGENTS rule that "a rule a tool can check gets a lint rule". Use it so the built-ins stay honest in the new format.
- **`engines` range plus a build stamp** (the `sdkMajor` written into the built artifact) to refuse a stale bundle.

**Skip**
- The `experimental_` prefix on every member, and three entry kinds (server, app, host). We have one runtime (the card webview) plus Swift. Use one `main.ts` and one `apiVersion`.
- Shimming React into a shared runtime. Our cards are separate webviews, so each plugin bundles what it uses.

---

## 2. OpenCode plugins

https://opencode.ai/docs/plugins/ · https://opencode.ai/v2/docs/build/plugins/

**Written/loaded.** A plugin is a JS/TS module in `.opencode/plugins/` (per project) or `~/.config/opencode/plugins/` (global), or an npm name listed in `opencode.json` `"plugin": [...]`. Bun loads them at startup; npm plugins are installed with Bun into `~/.cache/opencode/node_modules`. Load order is: global config, project config, global dir, project dir. Hooks run in that order, so later plugins see what earlier ones changed.

**Manifest.** There is none for local files. For npm plugins it is just the list in `opencode.json`:
```json
{ "$schema": "https://opencode.ai/config.json", "plugin": ["opencode-wakatime", "@my-org/custom-plugin"] }
```

**API shape.**
```ts
import type { Plugin } from "@opencode-ai/plugin"
export const MyPlugin: Plugin = async ({ project, client, $, directory, worktree }) => ({
  event: async ({ event }) => { if (event.type === "session.idle") await $`osascript -e '…'` },
  "tool.execute.before": async (input, output) => {
    if (input.tool === "read" && output.args.filePath.includes(".env")) throw new Error("no")
  },
  tool: { mytool: tool({ description: "…", args: { foo: tool.schema.string() }, async execute(args, ctx) { … } }) },
})
```
Hooks change an `output` object in place, and a hook can throw to veto the action.

**Hot reload.** None: you restart OpenCode. **Security:** none. The plugin gets Bun's `$` shell and full process rights.

**Take**
- **The entry signature.** One async function gets a context object and returns hooks. That is the simplest shape that is fully typed. Oriel can use `export default (oriel: Oriel, card: CardContext) => void | Promise<void>`, with events registered through `oriel.on(...)`.
- **Project-local plugin folders** (`.opencode/plugins/`) next to global ones. For Oriel: `~/.config/oriel/plugins/` plus a folder per project, on the herdr host.

**Skip**
- No manifest. We need a manifest because the native header and file-type matching must be known **before** any JS runs.
- An unrestricted `$` shell. Our `run` should go through Swift, with the cwd and environment set by the card.

---

## 3. VS Code webview extensions

https://code.visualstudio.com/api/extension-guides/custom-editors · https://code.visualstudio.com/api/extension-guides/webview · https://code.visualstudio.com/api/references/contribution-points

**Written/loaded.** An extension is an npm package. The extension host (Node) runs `main`. A webview is an iframe that the extension fills with HTML and talks to only through `postMessage`. Since 1.74, `activationEvents` such as `onCustomEditor:<viewType>` and `onCommand:` are created from `contributes`, so the extension loads lazily.

**Manifest:**
```json
{
  "name": "cat-customs", "version": "0.0.1", "engines": { "vscode": "^1.74.0" }, "main": "./out/extension.js",
  "contributes": {
    "customEditors": [{ "viewType": "catEdit.catScratch", "displayName": "Cat Scratch",
      "selector": [{ "filenamePattern": "*.cscratch" }], "priority": "default" }],
    "commands": [{ "command": "catEdit.refresh", "title": "Refresh", "icon": "$(refresh)" }],
    "menus": { "editor/title": [{ "command": "catEdit.refresh",
      "when": "activeCustomEditorId == catEdit.catScratch", "group": "navigation" }] }
  }
}
```
`priority: "option"` means the editor is used only when the user picks it with "Reopen With…". Header buttons are `menus.editor/title` entries. They are declared up front and shown or hidden with `when` context keys, which the extension sets with `setContext`.

**API shape.**
```ts
export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(vscode.window.registerCustomEditorProvider("catEdit.catScratch", provider,
    { webviewOptions: { retainContextWhenHidden: false } }));
}
interface CustomTextEditorProvider {
  resolveCustomTextEditor(document: TextDocument, panel: WebviewPanel, token: CancellationToken): void | Thenable<void>;
}
panel.webview.options = { enableScripts: true, localResourceRoots: [Uri.joinPath(ctx.extensionUri, "media")] };
panel.webview.onDidReceiveMessage(msg => …); panel.webview.postMessage({ type: "update", text });
// inside the webview
const vscode = acquireVsCodeApi();               // only once per page
vscode.postMessage({ type: "edit" });
const s = vscode.getState(); vscode.setState({ count }); // JSON, kept while the panel exists
```
CSP: `default-src 'none'; script-src ${webview.cspSource}; style-src ${webview.cspSource}`. Resources load only through `webview.asWebviewUri()`, which serves files only from inside `localResourceRoots`. For theming, the body gets the class `vscode-light`, `vscode-dark` or `vscode-high-contrast`, plus about 600 CSS variables such as `--vscode-editor-foreground` and `--vscode-editor-font-family`. `WebviewPanelSerializer` restores a panel after a restart from its `getState()` value.

**Hot reload.** None for real use: you press F5 to open an "Extension Development Host" window and run "Reload Window". **Security:** the extension host has full rights. Only the webview is sandboxed, by the iframe, the CSP and the resource roots.

**Take**
- **`selector.filenamePattern` + `priority: default | option`.** Use this as is in our manifest (`opens: [{ pattern: "*.md", priority: "default" }]`). It settles who wins when the markdown and preview built-ins both match.
- **Header controls declared in the manifest, state pushed at runtime.** VS Code splits the two: a static `menus` entry, plus `when` keys that change it. For Oriel: the manifest declares `controls[{ id, icon, title, kind: button|toggle|menu }]`, and the plugin calls `card.controls.update(id, { on, enabled, hidden })`. Clicks arrive as `card.on("control", id)`. Swift draws the header before the webview loads.
- **`getState`/`setState`**: synchronous to read, JSON, and cached in the page. Oriel should give the plugin the last saved state at load (`card.state`) and keep it across hot reload, restarts and relayout. One feature replaces both `retainContextWhenHidden` and the serializer.
- **Theme tokens as CSS variables plus a body class**, and **CSP with resource roots**. In WebKit that means a `WKURLSchemeHandler` for `oriel-plugin://<id>/` that serves only the plugin folder and the bundle, with a strict CSP header.

**Skip**
- The two-process split (extension host plus webview). Our "host" is Swift, so `main.ts` runs in the webview and calls the bridge directly. Skip `activationEvents` too: a card is created on demand, so loading is already lazy.
- A `when`-clause expression language. A plain `hidden`/`enabled` set from JS is enough.

---

## 4. Zed extensions

https://zed.dev/docs/extensions/developing-extensions · https://zed.dev/docs/extensions/capabilities · https://zed.dev/blog/zed-decoded-extensions

**Written/loaded.** An extension is a git repo with `extension.toml`. It is mostly declarative: languages, themes, snippets, grammars. Code (LSP, context server, debugger) is written in Rust, built to `wasm32-wasip2`, and run in Wasmtime through WIT interfaces.

**Manifest:**
```toml
id = "my-extension"
name = "My extension"
version = "0.0.1"
schema_version = 1
authors = ["Your Name <you@example.com>"]
description = "Example extension"
repository = "https://github.com/your-name/my-zed-extension"

[[capabilities]]
kind = "process:exec"
command = "gem"
args = ["**"]
```

**API shape.**
```rust
use zed_extension_api as zed;
struct MyExtension;
impl zed::Extension for MyExtension {
  fn new() -> Self { MyExtension }
  fn language_server_command(&mut self, id: &zed::LanguageServerId, wt: &zed::Worktree) -> zed::Result<zed::Command> { … }
}
zed::register_extension!(MyExtension);
```
The API crate is versioned (`zed_extension_api = "0.x"`), and Zed keeps old WIT versions working.

**Hot reload.** "Install Dev Extension" points at a folder and overrides the published version ("Overridden by dev extension"). It rebuilds when you reinstall, not on save. **Security:** capabilities (`process:exec`, `download_file`, `npm:install`) are declared with glob scopes. Users can narrow what is granted in settings with `granted_extension_capabilities`. A missing capability makes the API call return an error. It does not crash the extension.

**Take**
- **Capabilities declared in the manifest with glob scopes, and denied calls return errors.** For Oriel: `permissions: { run: ["git", "rg"], files: "card-root" | "home" | "any", network: [...] }`. Swift checks each bridge call and rejects with a typed error. Built-ins get the same check, so it gets tested.
- **`schema_version` in the manifest**, separate from the API version. It lets us change the manifest format later.
- **A dev folder overrides the installed plugin with the same id**, and the UI shows a badge for it.

**Skip**
- WASM and Rust. Our UI is a webview, and TypeScript is the point.
- A user settings list of granted capabilities. Show the manifest's permissions once, when the plugin is installed.

---

## 5. Obsidian plugins

https://docs.obsidian.md/Reference/Manifest · https://docs.obsidian.md/Reference/TypeScript+API/Plugin · https://github.com/pjeby/hot-reload

**Written/loaded.** Each plugin is a folder in `.obsidian/plugins/<id>/` with `manifest.json`, `main.js` (bundled by esbuild in the sample plugin) and `styles.css`. It runs in Obsidian's Electron renderer.

**Manifest:**
```json
{ "id": "sample-plugin", "name": "Sample Plugin", "version": "1.0.0", "minAppVersion": "0.15.0",
  "description": "Demonstrates some of the capabilities of the Obsidian API.",
  "author": "Obsidian", "isDesktopOnly": false }
```
A separate `versions.json` maps each plugin version to its `minAppVersion`, so older apps get the newest plugin build that still works for them.

**API shape.**
```ts
export default class MyPlugin extends Plugin {
  async onload() {
    this.registerView(VIEW_TYPE, (leaf) => new MyView(leaf));
    this.registerExtensions(["csv"], VIEW_TYPE);              // file type → view
    this.registerEvent(this.app.vault.on("modify", f => …));  // removed automatically on unload
    this.registerInterval(window.setInterval(…, 1000));
    this.addCommand({ id: "open", name: "Open", callback: () => … });
    const data = await this.loadData(); await this.saveData(data); // data.json
  }
  onunload() {}
}
class MyView extends ItemView {
  getViewType() { return VIEW_TYPE } getDisplayText() { return "CSV" }
  async onOpen() { this.addAction("refresh-cw", "Reload", () => …) }   // view header button
  getState() / setState(state, result)                                 // saved in the workspace layout
}
```

**Hot reload.** pjeby/hot-reload watches every plugin folder that has a `.git` folder or a `.hotreload` file. When `main.js`, `styles.css` or `manifest.json` changes, it disables and re-enables the plugin. Open views are closed and opened again; they get back the state saved through `setState`. **Security:** none. Plugins get full Node and Electron, and the store depends on review and on code being public.

**Take**
- **`register*` helpers that clean up on their own.** Every `oriel.watch`, `oriel.on` or timer is tied to the card's lifetime and released on close or reload, with no unsubscribe calls in plugin code. This gives clean hot reload almost for free.
- **`minAppVersion` + `versions.json`.** A plain minimum version is easier to reason about than a semver range. For Oriel: `minOriel: "0.9"` plus `apiVersion: 1`.
- **View `getState`/`setState` kept in the layout.** It confirms the per-card state design above: card state belongs in Oriel's layout save, next to the card.

**Skip**
- Imperative `addAction` header buttons. They exist only after JS runs, so the header flickers. Use manifest-declared controls.
- A class to extend (`extends Plugin`). A function plus a context object is shorter and easier to type.

---

## 6. Raycast extensions

https://developers.raycast.com/information/manifest · https://developers.raycast.com/api-reference/storage · https://developers.raycast.com/basics/create-your-first-extension

**Written/loaded.** An extension is an npm package of React/TSX commands. Each command runs in a separate Node worker. A custom React reconciler turns the component tree into **native** AppKit views (List, Detail, Form, ActionPanel), so plugin code never touches a DOM.

**Manifest** (`package.json`):
```json
{ "name": "my-ext", "title": "My Ext", "description": "…", "icon": "icon.png", "author": "me", "license": "MIT",
  "commands": [{ "name": "index", "title": "Search Issues", "mode": "view" }],
  "preferences": [{ "name": "token", "title": "API Token", "type": "password", "required": true, "description": "…" }],
  "dependencies": { "@raycast/api": "^1.80.0" } }
```

**API shape.**
```tsx
export default function Command() {
  const { token } = getPreferenceValues<Preferences>();
  return <List><List.Item title="x" actions={<ActionPanel><Action.CopyToClipboard content="x"/></ActionPanel>}/></List>;
}
await LocalStorage.setItem("k", "v"); const v = await LocalStorage.getItem<string>("k"); // per extension, encrypted
```

**Hot reload.** `npm run dev` (`ray develop`) builds on save and reloads the open command, with an error overlay. **Security:** process isolation only, plus store review of open-source code. There are no runtime permissions.

**Take**
- **Typed `preferences` in the manifest that the host draws as native settings** (textfield, password, checkbox, dropdown). For Oriel: plugin settings in the manifest, drawn by Swift in Settings, read with `oriel.settings.get()`, and secrets kept in Keychain.
- **Native controls described by JS.** `ActionPanel` is the same idea as our header controls. Keep it small: buttons, toggles and menus only.
- **`ray develop` as a single command.** Oriel's dev loop should need no CLI at all: drop a folder in, save, reload. Show build errors in the card, not only in logs.

**Skip**
- Turning a whole React UI into native views. Our cards are webviews on purpose.

---

## 7. Figma plugins

https://developers.figma.com/docs/plugins/manifest/ · https://developers.figma.com/docs/plugins/how-plugins-run/ · https://developers.figma.com/docs/plugins/api/figma-clientStorage/

**Written/loaded.** There are two parts. `main` runs in a sandboxed JS VM that has the `figma` API but no DOM. `ui` is HTML in an iframe with a null origin that has the DOM but no `figma` API. They talk with `postMessage`.

**Manifest:**
```json
{ "name": "MyPlugin", "id": "737805260747778092", "api": "1.0.0", "editorType": ["figma", "figjam"],
  "main": "code.js", "ui": "ui.html", "documentAccess": "dynamic-page",
  "networkAccess": { "allowedDomains": ["none"] } }
```
`networkAccess` also takes `reasoning` (why the plugin needs it) and `devAllowedDomains` (localhost, used only in development). The allowed domains are enforced as CSP. `permissions` lists extra access: `currentuser`, `activeusers`, `teamlibrary`, `payments`.

**API shape.**
```ts
figma.showUI(__html__, { width: 320, height: 480, themeColors: true });
figma.ui.onmessage = (msg) => { … }; figma.ui.postMessage({ type: "done" });
// ui.html
parent.postMessage({ pluginMessage: { type: "create" } }, "*");
onmessage = (e) => e.data.pluginMessage;
await figma.clientStorage.setAsync("k", value); await figma.clientStorage.getAsync("k");
```
`themeColors: true` adds `--figma-color-*` CSS variables to the UI and a `figma-dark` class.

**Hot reload.** The desktop app has a "Hot reload plugin" option in the plugin development menu: it reruns the plugin when `main` changes. **Versioning:** `api` is pinned per plugin and never upgraded automatically.

**Take**
- **`networkAccess.allowedDomains` + `reasoning` + `devAllowedDomains`, enforced by CSP.** Map this straight to our `connect-src`, so a markdown preview cannot send data anywhere. Use `devAllowedDomains` for a plugin that shows a local dev server.
- **A pinned `api` version that is never auto-upgraded.** Swift then keeps old bridge behaviour for older `apiVersion` values when we change it.
- **A `themeColors` opt-in.** Inject the theme variables, and add a reset stylesheet only if the plugin asks for it.

**Skip**
- The main/UI split. Swift already is our "main", and a second JS context only adds hops.
- Messages without types. Our bridge is typed request and response.

---

## 8. Tauri and Electron (bridge patterns)

https://v2.tauri.app/security/capabilities/ · https://v2.tauri.app/security/permissions/ · https://v2.tauri.app/concept/inter-process-communication/isolation/ · https://www.electronjs.org/docs/latest/api/context-bridge · https://www.electronjs.org/docs/latest/tutorial/context-isolation

**Tauri.** The frontend calls Rust commands with `invoke<T>(cmd: string, args?: InvokeArgs): Promise<T>`. Nothing is allowed by default. Capability files grant permissions per window or webview, and a permission can carry a scope:
```json
{ "$schema": "../gen/schemas/desktop-schema.json", "identifier": "main-capability",
  "description": "Capability for the main window", "windows": ["main"],
  "permissions": ["core:path:default", "core:event:default",
    { "identifier": "fs:allow-read-text-file", "allow": [{ "path": "$HOME/notes/**" }] }] }
```
Permissions are TOML (`[[permission]] identifier = "allow-x"; commands.allow = ["x"]`), and the JSON schemas are generated. The *isolation pattern* sends every IPC message through a sandboxed iframe that can check it and encrypts it with AES-GCM before it reaches the core.

**Electron.** A preload script runs with `contextIsolation` (default since v12) and exposes a narrow, safe-to-clone API:
```ts
contextBridge.exposeInMainWorld("api", { readFile: (p: string) => ipcRenderer.invoke("read", p) });
ipcMain.handle("read", (e, p) => { /* check e.senderFrame and p */ });
```
The docs say never to expose `ipcRenderer` itself. Validate the sender and the arguments in the main process.

**Take**
- **Scoped permissions with path variables** (`$HOME`, and for us `$CARD_ROOT` or `$PROJECT`). Swift resolves them per card and refuses paths outside them. Generate the TypeScript declarations for `oriel` from one Swift/JSON schema, the way Tauri generates its schemas.
- **The Electron rule: expose functions, never the channel.** In WebKit, use `WKScriptMessageHandlerWithReply` (it returns promises) behind a small injected `oriel` module. Swift checks the card id, plugin id and arguments on every call. JS never sees a raw `postMessage`.
- **Grant per webview.** Each card's webview carries only its own plugin's permissions, so one card cannot reach another plugin's capabilities.

**Skip**
- The isolation pattern's encryption iframe. Our bridge is in-process, and checking in Swift is enough.
- Separate capability files. Put permissions in the plugin manifest (one file per plugin).

---

## What this changes in our design

1. **Manifest** (must work before JS runs): `id, name, version, schemaVersion, apiVersion, minOriel, main, icon, opens[{pattern, priority}], controls[{id, icon, title, kind}], settings[{name, type, title}], permissions{files, run[], network[], devNetwork[]}`.
2. **Entry:** `export default (oriel: Oriel, card: Card) => void | Promise<void>`. Every subscription is tied to the card and cleaned up on its own. `card.state` is given at load and survives reload and restart. `card.controls.update(id, …)` changes a header control, and clicks arrive as `card.on("control", id)`. A plugin that claims a file can still return the card to the built-in (bb's `Original`).
3. **Hot reload:** build the candidate bundle. If esbuild or init fails, keep the old webview and show the error. If it succeeds, swap and pass `card.state` across. A dev folder overrides an installed plugin with the same id.
4. **Security:** a strict CSP from a custom scheme. `connect-src` comes from `permissions.network`. Swift checks every bridge call against the manifest scopes. Built-ins declare permissions too, and a lint/CI check confirms they use only the public `oriel` API (bb's "forkable" check).

## Summary

| System | Written / loaded | Manifest | API shape | Hot reload | Take | Skip |
|---|---|---|---|---|---|---|
| bb (get-bb) | TS package; server factory + React app; esbuild; host shims React | `package.json` `bb{name,server,app,branding}`, `engines.bbPluginSdk` | `plugin(bb)`; `definePluginApp(app => app.slots.fileOpener({extensions}))` | `bb plugin dev`, candidate generation, old set kept on failure | Candidate-then-swap reload; `Original` fallback; forkable built-ins lint; sdkMajor stamp | `experimental_` on everything; 3 entry kinds; shimmed React |
| OpenCode | TS/JS in `.opencode/plugins/` or npm, loaded by Bun | none (config list) | `async (ctx) => hooks{}`; hooks change `output` | restart | Function+context entry; global + project folders | No manifest; raw `$` shell |
| VS Code | npm ext host + iframe webview | `contributes.customEditors.selector.filenamePattern`, `priority`, `menus.editor/title`, `engines.vscode` | `registerCustomEditorProvider`, `postMessage`, `acquireVsCodeApi().getState/setState` | F5 dev host, Reload Window | filenamePattern+priority; declared header + runtime state; get/setState; CSP + resource roots + theme vars | Two-process split; `when` language; activationEvents |
| Zed | Rust→WASM (Wasmtime) + declarative files | `extension.toml` + `schema_version` + `[[capabilities]]` | `impl zed::Extension`, `register_extension!` | Install Dev Extension (overrides installed) | Scoped capabilities, denied calls return errors; schema_version; dev override | WASM/Rust; user grant list |
| Obsidian | folder `main.js` in Electron renderer | `manifest.json` `id, minAppVersion, isDesktopOnly` + `versions.json` | `class extends Plugin { onload(){ registerView/registerExtensions/registerEvent } }` | pjeby/hot-reload: watch, disable, enable | Auto-cleanup `register*`; minAppVersion; view state in layout | Imperative `addAction` header; base class; no sandbox |
| Raycast | React commands in a Node worker, drawn as native views | `package.json` `commands[]`, typed `preferences[]` | React components, `getPreferenceValues`, `LocalStorage` | `ray develop`, error overlay | Manifest settings drawn natively; native controls from JS; one-step dev loop | React for the whole UI |
| Figma | sandboxed main VM + null-origin UI iframe | `manifest.json` `api, editorType, main, ui, networkAccess{allowedDomains, reasoning, devAllowedDomains}, permissions` | `figma.showUI`, `ui.postMessage/onmessage`, `clientStorage` | desktop "Hot reload plugin" | Network allowlist as CSP + dev domains; pinned api; themeColors | Main/UI split; untyped messages |
| Tauri / Electron | web frontend + Rust / Node main | capabilities JSON + permission TOML / preload | `invoke<T>(cmd,args)` / `contextBridge.exposeInMainWorld` | app dev server | Scoped permissions with path variables; generated types; expose functions not channels; grants per webview | Isolation encryption iframe; separate capability files |
