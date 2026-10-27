# Plugins: what a future plugin system could use

Oriel has no plugins (see `docs/content/docs/future-work.mdx`). These are the facts and options found for
one, so a later design starts from evidence.

## What herdr offers

- **herdr plugins** (`herdr-plugin.toml`): actions, event hooks, startup commands and terminal panes. Their
  panes are terminals only; there is no browser or graphics pane (`pane.graphics.*` was removed in 0.9).
  Details: [../multiplexers/herdr.md](../multiplexers/herdr.md).
- **A placeholder pane** can hold a plugin's place in herdr's layout: `layout.apply` starts a pane with a
  label and an inert command in one call (then `pane.move` places it). The label is the one durable
  free-form field on a pane: it survives moves and a cold restart; a metadata token does not. After a cold
  restart the pane comes back as a plain shell with its label.
- One idle placeholder costs about 110 KB in the server plus one `cat`.

## How to draw plugin UI

| Option | Verdict |
|---|---|
| A small web page in a `WKWebView` per card | Simplest; any web library; looks native only with care (`system-ui`, `ui-monospace`, `color-scheme`, CSS variables). A WebContent process costs 120–200 MB. |
| React in JavaScriptCore, a JSON tree drawn as SwiftUI (Raycast 1.x's model) | Fully native look; needs our own component kit, a reconciler and a build tool. Measured below. |
| A hybrid of the two (native kit with a web view escape hatch) | Both costs. |
| React Native embedded | A large dependency, two forks (iOS, macOS), still needs a kit. |
| Native Swift plugins loaded at runtime | Needs the library-validation entitlement; runs in-process; App Store rules forbid it on iOS. |
| ExtensionKit | macOS needs a sandboxed extension in a notarized container app and user approval; iOS hosts only its own extensions. |
| WASM components (Zed's model) | No UI; a capability model worth copying for finer permissions. |
| herdr's own TUI plugin panes | Work today as terminals; no native UI. |

**Measured** (React 19 and react-reconciler in plain system JavaScriptCore, a 500-row list and a detail,
the full 80 KB JSON tree per commit, Apple Silicon): bundle 143 KB minified, 45 KB gzip; a row select 2–3 ms
with the JIT, about 2 ms without; 20 updates in a row 12–16 ms with the JIT, 41–47 ms without; about 3 MB
per JavaScriptCore context. The host config is about 60 lines; the only polyfills are `setTimeout`,
`queueMicrotask` and `console`. Full-tree commits are fine at this size; heavy work belongs on the machine.

## How plugins reach a remote machine

| Option | Verdict |
|---|---|
| Run plain CLIs over the existing SSH connection (the relay) | Enough for git history, diffs, file views and port lists; nothing installed on the server. |
| A web page reaching the machine's `localhost` through an SSH port forward | Works without an agent; needs `AllowTcpForwarding`. |
| Our own small agent over SSH stdio (cmux, Zed, VS Code style) | Only when SSH session limits, latency, file watching or a server without forwarding make it necessary. |
| Plugin backends on the server, UI local | An install per machine; no gain over the agent. |
| herdr as the transport | herdr has no generic file or port API. |
| An overlay network (Tailscale) | The user's choice, not ours to require. |

Others: cmux, Zed and VS Code ship a server agent mostly to keep terminals alive or run language servers;
herdr already keeps the terminals alive, and `sshd` already reads files, runs git and forwards ports.

## Sources

- Raycast: [How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work),
  [A Technical Deep Dive Into the New Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast).
- herdr: `herdr api schema --json`, its `docs/plugins.mdx`, discussion
  [#1367](https://github.com/herdrdev/herdr/discussions/1367) (plugin panes after a restart).
- cmux: https://cmux.com/docs/ssh.
