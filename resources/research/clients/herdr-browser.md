# herdr-browser (ogulcancelik): Chromium inside a herdr pane

**Status: DEPRECATED** (HEAD `ab5c60b`). The successor is `zenbu-labs/terminal-browser` (Electron offscreen rendering → raw RGBA frame files → `pane.graphics.stream` `{"format":"rgba","file":{"path":…},"sequence":42,"revision":0}` with herdr acks).
The manifest was deleted at HEAD; the version below is from commit `be6888b`.

**How a browser pane is represented in herdr.** It is a **herdr plugin pane**: an ordinary terminal pane whose process is the plugin's viewer.
```toml
id = "official.browser"
[[panes]]
id = "browser"
title = "Browser"
placement = "split"
command = ["bun", "run", "src/viewer.ts"]
[[link_handlers]]
id = "localhost"
pattern = "^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]+)?([/?#].*)?$"
action = "open-localhost"
```
It is opened like this (`src/herdr.ts`):
```
herdr plugin pane open --plugin official.browser --entrypoint browser --placement split|tab|zoomed|overlay
  [--direction right|down] [--target-pane P] --env HERDR_BROWSER_INITIAL_URL=<url> --env HERDR_BROWSER_VIEW_ID=<id> --focus|--no-focus
→ {"result":{"type":"plugin_pane_opened","plugin_pane":{"pane":{"pane_id":"…"}}}}
```
**The URL is stored only in the process environment** (`HERDR_BROWSER_INITIAL_URL`) and in the plugin daemon's own view registry (view_id ↔ pane_id ↔ url/title/tabs, `herdr-browser views`). **herdr's pane metadata does not record it.**
herdr injects these variables into the pane process: `HERDR_PANE_ID`, `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`, `HERDR_PLUGIN_ID`, `HERDR_PLUGIN_ENTRYPOINT_ID`, `HERDR_CELL_WIDTH_PX/HEIGHT_PX`.

**Rendering.**
- A Bun daemon owns Chromium over CDP.
- The viewer turns `Page.startScreencast` frames into PNG and sends them through herdr's graphics methods (`src/herdrGraphics.ts`):
  - `pane.graphics.info {pane_id}` → `{type:"pane_graphics_info", cell_width_px, cell_height_px}`
  - `pane.graphics.set {pane_id, format:"png", image_width, image_height, data_base64, placement:{viewport_col, viewport_row, grid_cols, grid_rows}}`
  - `pane.graphics.clear {pane_id}`
  - `pane.graphics.stream {pane_id}`: after the JSON ack, the socket carries `<json header {format,image_width,image_height,data_length,placement}>\n<png bytes>` frames.
- This needs `[experimental] kitty_graphics = true` in the herdr config.
- Terminal mouse, wheel and key input is mapped to CDP `Input.dispatch*`.
- A view-scoped **CDP gateway** (`cdp_http_url` / `browser_ws_url`) lets agents drive the visible browser with Playwright `connectOverCDP` or Chrome DevTools MCP.

## 8. herdr-plannotator (plannotator): "Herdr Browser panes"

Small glue code.
1. Plannotator's external-presenter hook runs `bin/herdr-plannotator-present` with one JSON request.
2. The helper runs `herdr plugin pane open --plugin official.browser --entrypoint browser --placement zoomed --target-pane <agent pane> --env HERDR_BROWSER_INITIAL_URL=<url> --focus` and parses the pane id.
3. **Readiness** is checked with `herdr pane wait-output <pane> --match <url origin> --source visible --timeout 5000`. The viewer draws its URL bar as text.
4. Close: `herdr plugin pane close <id>`, falling back to `herdr pane close`.

Capability check: `herdr plugin list --plugin official.browser --json` → `result.plugins[].{plugin_id, enabled, plugin_root}`. It then greps the installed `src/viewer.ts` for `HERDR_BROWSER_INITIAL_URL`, because the plugin version was never bumped.
Approvals stay inside the web page.
