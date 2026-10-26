# Plugin UI: options and evidence

How Oriel could draw plugin panes, if it ever gets them (not built; see `docs/content/docs/future-work.mdx`).
The last design chose a small web page in a `WKWebView` per card; the main alternative is a React kit drawn
as native SwiftUI. This file keeps the evidence for both.

## 1. Raycast, the model for a native kit

### 1.1 Runtime and sandboxing
Source: [How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work), 2023-05-31.
- **First attempt:** "one JavaScriptCore instance per extension", in an
  XPC extension-host process. The UI was a JSON component tree rendered by
  custom AppKit components. Developers wanted npm packages and familiar React
  state, and polyfilling Node and web APIs became "an endless work stream".
- **Shipped:** React on **Node.js**. Raycast downloads and manages Node and
  checks its integrity. It runs one child Node process, and each extension
  gets a **worker thread** (a V8 isolate with a heap limit). The app talks to
  Node over **JSON-RPC on stdio** (DispatchIO), and only registered messages
  are allowed.
- **Rendering:**
  - A custom **react-reconciler** builds a JSON "render tree" on every pass.
  - Each tree is diffed against the last one as **JSON Patch**, and gzipped
    above a size threshold.
  - Swift view models (with bitsets of what changed) drive custom **AppKit**
    components (not SwiftUI).
  - "v = f(s) across process boundaries."
- **Sandboxing "considered ... but rejected":** a process per extension is
  too expensive, `sandbox-exec` is unsupported, and an engine-level sandbox
  is slow. Their aside: "Ironically, using JavaScriptCore like we did in the
  first attempt we discarded, would have given us a sandbox for free."
  Security comes from open source plus review, and "extensions are not
  further sandboxed" ([security](https://developers.raycast.com/information/security)).

### 1.2 Raycast 2.0
Source: [A Technical Deep Dive Into the New Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast), 2026-05-14.
- **Structure:**
  - Swift/AppKit and C#/WPF host shells.
  - One React + TypeScript **web frontend** in WKWebView or WebView2.
  - One long-lived **Node backend** that "owns ... the extension runtime".
  - A Rust core.
- **Memory:**
  - WebContent ~120–200 MB, Node 150–200 MB.
  - An empty WebView is "about 50 MB", and a bare Node process ~12 MB.
  - v1 used 200–300 MB in total; v2 uses 350–450 MB.
- **Native feel took deliberate work:**
  - no `cursor: pointer` and no hover highlights;
  - popovers and tooltips are native windows;
  - workarounds for WebKit throttling, blank frames and flicker
    (`_doAfterNextPresentationUpdate`).
  - "Some native niceties are harder ... accessibility behaviors, drag and
    drop edge cases, or IME handling."
- **How extension UI renders in 2.0 [inference]:**
  - The developer changelog says "Raycast 2.0 brings the extension API to the
    new Raycast desktop app". In 2.3.0: "Reduced memory usage and the amount
    of data sent when updating extension views"
    ([changelog](https://developers.raycast.com/misc/changelog.md)).
  - The API (List, Detail, ...) did not change, and all UI now lives in the
    web frontend. So the same JSON render tree is now drawn by DOM components
    instead of AppKit.
  - **Lesson for us:** a fixed component vocabulary outlived a full renderer
    rewrite. Extension code did not change.
- Raycast for iOS has no third-party extensions (AI, Notes, Snippets,
  Quicklinks; [manual](https://manual.raycast.com/ios)).

## 2. Rendering options

### 2.1 (A) React in a WebView with our own DOM component kit
How: each plugin card is a `WebPage`. The page loads the plugin bundle from a
custom scheme. Our kit draws `List`, `Detail` and the rest as DOM and CSS that
look like the app (dark, SF fonts, ANSI palette). Native chrome surrounds it.
Revision 4 already designed the scheme handler, CSP, content rules and bridge
(DESIGN §10.4.7, §14.5).
- **Pros:**
  - Any DOM library works (react-markdown, react-diff-view, d3).
  - Custom drawing is free (SVG, canvas).
  - WebKit text layout is excellent (Raycast credits it for chat and
    Markdown).
  - Safari Web Inspector.
  - The JIT works on iOS too, because WebContent runs out of process.
  - About 1k fewer lines for us than B.
- **Cons:**
  - **Memory:** one WebContent process per live card, ~50 MB empty and
    120–200 MB in use (Raycast's numbers). Six live cards can reach ~1 GB.
    Revision 4 had to cap live pages at 6 on Mac and 2 on iPhone.
  - **Nativeness is imitation.** Raycast spent a team-year on throttling,
    flicker, popovers and hover. Text selection, accessibility, focus and IME
    all differ from the rest of our SwiftUI app.
  - **Authors can skip the kit.** Arbitrary DOM means looks drift, unless
    every plugin is reviewed.
  - **Security:** repository content (a Markdown file) rendered as HTML is
    the top risk. XSS reaches the bridge, and the bridge reaches `exec`.
    Revision 4 needed CSP on every response, no inline script, content rules,
    a WebRTC removal script, navigation rules and per-origin data stores.
  - Two input stacks (DOM focus versus app shortcuts) inside one card.

### 2.2 (B) React in JavaScriptCore, JSON tree to native SwiftUI
How: one `JSVirtualMachine` + `JSContext` per card. The app first evaluates a
prelude (React, our reconciler, the API runtime, ~140 KB), then the plugin's
bundle. Each commit calls `__host.commit(json)`. Swift decodes it into a
`Node` tree and draws it with our SwiftUI components. Events go back as
`__dispatch("<nodeId>.<prop>", args)`.
- **react-reconciler in plain JSC works:**
  - React 19.3 + react-reconciler 0.34 run in the system `jsc`, with and
    without the JIT.
  - The host config is ~60 lines.
  - The only polyfills needed are `setTimeout`/`clearTimeout`,
    `queueMicrotask` and `console` (`poly.js`). React's scheduler falls back
    to `setTimeout`.
- **JIT:**
  - A `JSContext` inside an iOS app has no JIT ("disabled when we use JSC
    inside iOS apps", a 7.5× slowdown on a CPU benchmark,
    [Coote 2020](https://dev.to/alastaircoote/to-jsc-or-not-to-jsc-running-javascript-on-ios-in-2020-44ba)).
    It runs on the LLInt interpreter.
  - For UI-sized work it does not matter: no JIT, 500 rows, ~2 ms per update
    (§2.6).
  - On macOS the JIT works in-process (measured with the system JSC). Whether
    our Hardened Runtime build needs `com.apple.security.cs.allow-jit` for the
    JIT is unchecked.
- **Threading:**
  - "all other threads attempting to use the same virtual machine must wait.
    To run JavaScript concurrently on multiple threads, use a separate
    JSVirtualMachine instance for each thread"
    ([docs](https://developer.apple.com/documentation/javascriptcore/jsvirtualmachine)).
  - So: one VM and one serial `DispatchQueue` per card. Decode on that queue,
    publish to `@MainActor`.
  - Suspending the queue pauses all timers and events while the card is off
    screen (one line).
- **Debugging:** `JSContext.isInspectable` (macOS 13.3+, iOS 16.4+,
  [docs](https://developer.apple.com/documentation/javascriptcore/jscontext/isinspectable))
  gives Safari Web Inspector with breakpoints and console.
- **No hard kill:** `JSContextGroupSetExecutionTimeLimit` exists only in
  WebKit's `JSContextRefPrivate.h`
  ([source](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextRefPrivate.h)).
  It is not in the SDK headers [verified: the macOS SDK's
  `JavaScriptCore.framework/Headers` has no such file]. DPLA §3.3.1(A):
  "must not use or call any private APIs". So a runaway loop cannot be
  interrupted, and there is no public heap limit either (§7.4).
- **Prior art:**
  - Raycast 1.x (AppKit, Node).
  - [react-watchos](https://github.com/emindeniz99/react-watchos/blob/main/docs/research.md):
    React 19 + reconciler 0.33 in QuickJS, JSON tree, SwiftUI interpreter,
    full-tree commits ("our trees are tens of nodes"). It notes that 2.5.2
    allows bundled interpreted JS.
  - react-tvml, Ink and react-three-fiber (custom reconcilers).
  - [Valdi](https://github.com/Snapchat/valdi) (Snap's TSX-to-native views,
    not React).
  - [LiveView Native](https://github.com/liveview-native) (a server-sent tree
    rendered by SwiftUI).
- **Pros:**
  - **Really native:** SwiftUI `List`, text selection, VoiceOver, Dynamic
    Type, context menus and keyboard. It is the same Markdown renderer as the
    chat view (DESIGN §11.1) and the same palette as the terminal.
  - **~3 MB per card**.
  - **The sandbox comes free.** The context has no DOM, network, file system
    or `require`, only what we inject. There is no HTML anywhere, so
    repository text cannot become script.
  - One look by construction, which is what the user asked for: "default
    components ... look similar in style".
  - Same engine on both OSes. No JavaScript code needs `#if`.
- **Cons:**
  - Plugins get **only our components**. A commit graph or chart needs the
    escape hatch (C) or a new kit component from us.
  - npm packages that touch the DOM or Node do not work (react-markdown,
    react-diff-view). Pure JS does (`diff`, `parse-diff`, `date-fns`, a
    Markdown lexer).
  - We own a versioned component vocabulary forever. Raycast has done it
    since 2021 and kept it through a renderer rewrite.
  - Controlled text fields would make a round trip per key. So text fields
    are native-owned: JS gets `onChange` and its `value` is applied only when
    it differs from what JS last saw.
  - In-process: a bug in our bridge can crash the app (Raycast moved
    extensions to another process; we cannot on iOS).
  - Heavy compute is slow without the JIT. Rule: heavy work runs on the host
    (`git` does the diff), and `Diff` parses unified diff text natively.

### 2.3 (C) Hybrid: B plus a `<WebView>` escape hatch
`<WebView source="graph.html" data={json} onMessage={fn} />`:
- It loads a file from the plugin's own `dist/` over
  `oriel-plugin://<plugin-id>/`.
- CSP: `default-src 'self'; script-src 'self'`. No network. No `exec` and no
  API inside the page.
- The page gets only the `data` JSON (re-sent on change) and may
  `postMessage` back. The JS treats those messages as untrusted.
- XSS inside it gains nothing beyond what the page can already do.
- It counts toward the live-web-page cap (6 on Mac, 2 on iPhone). It reuses
  the web page plugin's `WebPage` code and revision 4's scheme handler and
  CSP.

So nativeness is the default, and arbitrary drawing is possible without
giving web content any power.

### 2.4 (D) React Native embedded (iOS + react-native-macos)
- **What it is:** two forks to keep in step: facebook/react-native for iOS
  and [microsoft/react-native-macos](https://github.com/microsoft/react-native-macos),
  "a working fork of facebook/react-native" that trails upstream.
- **Cost:** a large native dependency (Hermes, Yoga, Fabric, CocoaPods)
 . Each plugin needs either its own RN host (heavy) or a
  shared one (no isolation).
- **Look:** RN components (`View`, `Text`, `FlatList`) are not our design
  system. We would still write the kit on top, and RN views are UIKit/AppKit
  inside a SwiftUI app.
- **What it adds over B:** Yoga layout, which we do not need for a fixed kit.
- **Verdict:** reject. Everything good about it (React to native) is B's ~60
  lines plus our SwiftUI kit, without the dependency.

### 2.5 Measured (a spike)
git-history-like `list` with 500 `item`s plus a `detail`. Every commit
serialises the full JSON tree (80 KB). Run on an Apple Silicon Mac, system
`jsc`.

| | JIT | `--useJIT=false` (like iOS) |
|---|---|---|
| Bundle: React + reconciler + plugin | 143 KB min, 45 KB gzip | same |
| One row selection (setState → commit → stringify) | 2–3 ms | ~2 ms |
| 20 updates in a row | 12–16 ms | 41–47 ms |
| Process footprint: 1 / 10 live JSContexts (Swift, one VM each) | 8.6 / 31.7 MB (base 2.0) | — |

- Full-tree commits are fine at this size. Add JSON Patch (Raycast) only if
  a profile shows big trees hurting.
- iPhone CPUs are slower than this Mac, which is still under
  one frame.

- React 19 and react-reconciler run in plain system JavaScriptCore, with and without the JIT. The host config is about 60 lines; the only polyfills are `setTimeout`/`clearTimeout`, `queueMicrotask` and `console`.

## 3. Other ways to run plugin code

### 3.1 Native Swift plugins loaded at runtime (bundles, dylibs)
How: `Bundle(url:).load()` on a `.bundle` that links a shared
`OrielPluginKit` framework and returns a SwiftUI view.
- **macOS signing.** The app ships with Hardened Runtime (DESIGN §14.1).
  Library validation "prevents a program from loading frameworks, plug-ins, or
  libraries unless they're either signed by Apple or signed with the same Team
  ID as the main executable." Third-party bundles need
  `com.apple.security.cs.disable-library-validation`, and then "Gatekeeper runs
  extra security checks on programs that have it disabled." [docs]
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation
  Downloaded bundles are also quarantined, so each author must sign and
  notarize them. [recall]
- **ABI.** The Swift standard library ABI has been stable on Apple platforms
  since Swift 5.0. A plugin API framework also needs module stability (built
  with `BUILD_LIBRARY_FOR_DISTRIBUTION`), and every API change must follow
  library-evolution rules. Otherwise plugins break on each Xcode update.
  [recall]
- **Security:** the plugin runs in the app's process with the user's full
  rights and access to the app's SSH connections. A plugin crash crashes the
  app.
- **iOS: impossible.** Guideline 2.5.2 bans downloading or running code that
  "introduces or changes features or functionality of the app", and iOS does
  not load code signed by another team. [docs]
  https://developer.apple.com/app-store/review/guidelines/
- **Precedent:** Xcode stopped loading third-party in-process plugins in
  Xcode 8 (the end of Alcatraz) and moved to out-of-process Source Editor
  Extensions. [recall]
- **Remote hosts:** a native plugin still cannot run `git` on a remote host. It
  needs the same exec bridge as every other option.
- Verdict: **reject.** It works on macOS only, needs a signing hole, gives
  plugins full power in our process, and has the worst ABI story.

### 3.2 First-party native only (compiled in)
How: each kind is Swift code in the app, chosen by the label prefix.
- Pros: the most native result (SwiftUI, Liquid Glass, accessibility, AppKit
  text). The fastest. Works on iOS. One codebase. No security surface.
- Cons: no third parties. Every new kind needs an app release, and on iOS an
  App Review.
- Verdict: **keep it as L2** for the few kinds that must be native. Today that
  is only the web page (it needs `WebPage`, per-host data stores and SSH port
  forwards, DESIGN §10.3). It is not a plugin *system*.

### 3.3 Apple ExtensionKit (remote SwiftUI views)
API (exact names):
- Host side: `EXHostViewController` ("hosts remote views provided by an app
  extension"): **macOS 13.0+, iOS/iPadOS 26.0+, Mac Catalyst 26.0+**, with
  `EXHostViewController.Configuration`, `makeXPCConnection()` and
  `EXHostViewControllerDelegate`. [docs]
  https://developer.apple.com/documentation/extensionkit/exhostviewcontroller
  There is no SwiftUI host view, so it needs a `UIViewControllerRepresentable`
  or `NSViewControllerRepresentable`.
- `EXAppExtensionBrowserViewController` lets the user turn extensions on or off.
  "App extensions you include inside your host app's bundle are enabled by
  default, but extensions that ship in separate apps are disabled by default."
  [docs]
  https://developer.apple.com/documentation/extensionkit/exappextensionbrowserviewcontroller
- Discovery: `AppExtensionIdentity` and its matching sequence. Extension side:
  `AppExtension` with an `AppExtensionScene`. `AppExtensionPoint` is
  documented from iOS 26 (Apple forums thread 802846, search snippet).
  [recall + snippet]
- I found **no API named `EXAppExtensionBrandedHostView`** in the docs or by
  search.

Facts that decide it:
- **iOS 26: "an app can only host extensions that it contains"** (Apple DTS on
  forums thread 802846, search snippet; the page itself was behind a
  verification wall). KhaosT/UIExtensionExample: "iOS 26 enables ExtensionKit
  for third party apps... to host custom UIs from the bundled extension."
  So on iOS, third-party extensions are not possible today.
- macOS: "ExtensionKit will refuse to load any extensions that do not have the
  sandbox entitlement set." Extensions "must be bundled and delivered within a
  .app." Each one needs user approval, and approval state lives in System
  Settings › Login Items & Extensions. (Matt Massicotte,
  https://www.massicotte.org/extensionkit-intro/, who built ChimeKit on it.)
 
- So a third-party author must ship and notarize a Mac **app** that holds a
  sandboxed extension, and the user must approve it. The extension still has to
  call back to our app over XPC to run `git` on a remote host.
- Precedents: Chime / ChimeKit; Final Cut Pro workflow extensions (shipped
  inside container apps); Audio Unit v3 remote views in Logic. Xcode Source
  Editor Extensions use the older NSExtension with no UI. [recall]
- Pros: real SwiftUI out of process, crash isolation, Apple-supported
  sandboxing.
- Verdict: **reject for v1.** Third parties cannot use it on iOS. On macOS the
  cost per author (a containing app, sandbox, notarization, approval) and the
  XPC API surface are high, and the result has the same remote-exec bridge as
  web plugins. Revisit only if Apple allows cross-app hosting on iOS.

### 3.4 Web plugins (HTML/JS in WebKit plus a message bridge)
How: the plugin is a folder (`index.html` plus assets) built with any web
stack. The app shows it in SwiftUI `WebView`/`WebPage` (macOS 26, iOS 26, the
same type the web pane uses). It serves the files through a custom scheme and
injects a small `oriel` object that posts messages to Swift.
- **Platform APIs** (all [docs]):
  - `WebPage.Configuration.urlSchemeHandlers: [URLScheme: any URLSchemeHandler]`,
    where `URLSchemeHandler.reply(for:)` returns an async sequence of response
    and data.
  - `WebPage.Configuration.userContentController` (a `WKUserContentController`):
    `WKUserScript` and `WKScriptMessageHandlerWithReply` give promise-style
    calls from JS.
  - `WebPage.callJavaScript(_:arguments:in:contentWorld:)` pushes events into
    the page.
  - `WebPage.NavigationDeciding.decidePolicy(for:preferences:)` controls
    navigation.
  - `WebPage.isInspectable` turns on Safari Web Inspector.
  - `webViewContentBackground(.hidden)` lets the SwiftUI background show
    through the page.
  - `WKContentRuleListStore` compiles block rules that apply to every load.
- **Precedents:**
  - VS Code webviews (https://code.visualstudio.com/api/extension-guides/webview):
    `acquireVsCodeApi()` plus `postMessage`, theme CSS variables such as
    `--vscode-editor-foreground` and body classes `vscode-dark`/`vscode-light`,
    `localResourceRoots`, a CSP the docs recommend, `getState`/`setState`. The
    docs warn that `retainContextWhenHidden` "has high memory overhead".
  - Figma: plugin UI in an `<iframe>` that talks only by message passing. "The
    security properties of the sandbox are guaranteed by browser vendors."
    (https://www.figma.com/blog/how-we-built-the-figma-plugin-system/)
  - Obsidian: plugins are JS. Its manifest has `isDesktopOnly`
    (https://docs.obsidian.md/Reference/Manifest), so **community JS plugins
    run in the Obsidian iOS app**. That is an App Store precedent. Obsidian
    admits it "cannot reliably restrict plugins to specific permissions"
    (https://obsidian.md/help/plugin-security), because its plugins run in the
    app's own context. Ours run in an isolated web view.
  - **Raycast v2 moved its own UI to React in WKWebView** inside a Swift shell:
    "a native app that uses web for its UI". Its numbers: an empty WebView costs
    about 50 MB, and WebContent uses 120–200 MB in use.
    (https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
  - VS Code **deprecated its Webview UI Toolkit** on 2025-01-01 and archived it
    (https://github.com/microsoft/vscode-webview-ui-toolkit/issues/561). Lesson:
    ship CSS variables and a base stylesheet, not a component library.
- **Looking native:**
  - `font: -apple-system-body` or `system-ui` gives SF Pro and follows Dynamic
    Type on iOS. `ui-monospace` gives SF Mono.
  - `color-scheme: light dark` and injected `--oriel-*` variables (§6.4) supply
    the app's card colours, ANSI palette, terminal font and radius.
  - No real vibrancy inside the page. That matches DESIGN D25: cards are
    opaque, and glass is for chrome only. The app draws the card header and
    toolbar natively, so only the body is web.
- **Sandboxing:** WebKit's WebContent process sandbox; a custom scheme origin per
  (host, plugin); a CSP header from the scheme handler; a content rule list that
  blocks `http(s)`/`ws(s)`; a navigation decider that keeps the page on its own
  scheme. No network at all.
- **Remote data:** every host access goes through the bridge to the existing
  `Exec`. The plugin never sees SSH.
- **iOS:** works. App Store analysis is in §8.
- **DX:** any bundler (Vite, esbuild). Safari Web Inspector. `herdr plugin link`
  plus the card's Reload button. A small `oriel.d.ts`.
- **Performance:** one WebContent process per live plugin page (about 50 MB
  each, from Raycast's numbers). Cap the live pages (§7).
- Verdict: **choose for third parties (L1).** One mechanism covers macOS and
  iOS, the sandbox is the browser's, every web skill and library works, and the
  card reuses the web pane's `WebPage` code.

### 3.5 herdr's own TUI plugin panes
Real examples, all installed with `herdr plugin install`:
- `persiyanov/herdr-reviewr`: diff review with line comments sent back to
  Claude, Codex, OpenCode or Pi. A Rust binary.
- `smarzban/herdr-file-viewer`: tree, diffs, rendered Markdown through
  glow, delta and bat.
- `alexarthurs/herdr-sidebar`: file explorer and source control.
- `ChmaraX/herdr-gitview`.
- plannotator, which opens its UI in "Herdr Browser panes"
  (`../clients/herdr-browser.md`).

What the app gets for free:
- They are normal herdr panes. They already draw in terminal cards through
  `terminal session` frames.
- They run on the host next to the data, on every host, on iOS too, with mouse
  support through `terminal.mouse`.
- libghostty's theme recolours their ANSI palette to match the app.
- herdr TUI users see the same pane.
- Install, update, trust preview and marketplace are herdr's.

Limits:
- A monospace cell grid. No real images (herdr removed `pane.graphics` in 0.9;
  `design.html`).
- Keyboard-first. Poor on touch. On iPhone, an observer gets a fixed 160×50
  screen (DESIGN §7.6).
- One PTY size and one controller per pane.
- No native text selection, scrolling or accessibility.
- `popup` entrypoints cannot be shown at all (no pane id).
- After a herdr restart the pane becomes a shell, because plugin `launch_argv`
  is not re-run [verified today]. Its label stays as the entrypoint title.

Verdict: **L0, always on.** The only app work is to list the host's
`split`/`tab` pane entrypoints in the "new pane" picker (§5.3).

### 3.6 WASM components (Zed model)
- Zed extensions are Rust compiled to WASM components, with WIT interfaces run
  by Wasmtime (https://zed.dev/blog/zed-decoded-extensions).
- **They provide no UI:** "languages, themes, debuggers, snippets, and MCP
  servers" (https://zed.dev/docs/extensions/developing-extensions).
- Zed has a good **capability model** to copy later: `process:exec` with
  command and args patterns, `download_file` by host, and a user setting
  `granted_extension_capabilities` (https://zed.dev/docs/extensions/capabilities).
- For us, WASM handles logic only, so we would still need option 2.4 or 2.5 for
  the UI.
- On iOS a WASM runtime outside WebKit must be an interpreter, such as
  swiftwasm/WasmKit. [recall]
- WebKit already runs WASM inside a web plugin. A plugin can bundle a
  WASM diff engine or syntax highlighter today. That needs `'wasm-unsafe-eval'`
  in the CSP (§6.5).
- Verdict: **reject as a separate system.** It is free inside L1.

## 4. App Store rules (an iOS app)

### 4.1 App Store analysis
- **The rule texts:**
  - Guideline 2.5.2: apps may not "download, install, or execute code which
    introduces or changes features or functionality of the app"
    ([guidelines](https://developer.apple.com/app-store/review/guidelines/)).
  - 4.7 allows "HTML5 and JavaScript mini apps ... and plug-ins". It requires
    4.7.2 (no native platform APIs without permission), 4.7.3 (consent before
    sharing data), 4.7.4 (an **index with universal links** of software
    offered in the app) and 4.7.5 (age gating).
  - DPLA §3.3.1(B): "Interpreted code may be downloaded to an Application but
    only so long as such code: (a) does not change the primary purpose ...
    (b) does not bypass signing, sandbox, or other security features of the
    OS; and (c) ... does not create a store or storefront" [docs: Apple
    Developer Program License Agreement PDF, read today].
- **Climate:**
  - In early 2026 Apple pulled "Anything" and blocked Replit and Vibecode
    updates under 2.5.2. Commentary lists "plugin systems adding post-review
    functionality" as at risk
    ([appcompliance.io](https://appcompliance.io/blog/apple-vibe-coding-crackdown-guideline-2-5-2/),
    [secondary]).
  - Obsidian still ships community JS plugins on iOS, with an in-app
    catalogue ([help](https://obsidian.md/help/community-plugins)).
- **Our position for the later setting:**
  - The code is the user's own, copied from their own Mac.
  - The app offers no catalogue or storefront (so 4.7.4 does not apply).
  - The primary purpose is unchanged: plugin panes are views of the user's
    own servers.
  - The API exposes no iOS platform API beyond clipboard write and opening a
    URL after a confirm.
  - The JS runs inside JavaScriptCore and bypasses nothing.
- Risk: medium. That is why v1 ships without it, and why the
  fallback is simply to remove the setting.

## Sources
- Raycast: [How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work) (2023-05-31) ·
  [A Technical Deep Dive Into the New Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast) (2026-05-14) ·
  [Manifest](https://developers.raycast.com/information/manifest) · [UI](https://developers.raycast.com/api-reference/user-interface) ·
  [Detail](https://developers.raycast.com/api-reference/user-interface/detail) · [Actions](https://developers.raycast.com/api-reference/user-interface/actions) ·
  [Navigation](https://developers.raycast.com/api-reference/user-interface/navigation) · [Toast](https://developers.raycast.com/api-reference/feedback/toast) ·
  [Storage](https://developers.raycast.com/api-reference/storage) · [Cache](https://developers.raycast.com/api-reference/cache) ·
  [Environment](https://developers.raycast.com/api-reference/environment) · [Preferences](https://developers.raycast.com/api-reference/preferences) ·
  [useExec](https://developers.raycast.com/utilities/react-hooks/useexec) · [usePromise](https://developers.raycast.com/utilities/react-hooks/usepromise) ·
  [Lifecycle](https://developers.raycast.com/information/lifecycle) · [CLI](https://developers.raycast.com/information/developer-tools/cli) ·
  [Security](https://developers.raycast.com/information/security) · [Changelog](https://developers.raycast.com/misc/changelog.md) · [iOS manual](https://manual.raycast.com/ios)
- Apple: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (2.5.2, 4.7) ·
  [Apple Developer Program License Agreement](https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-English.pdf) (§3.3.1 A, B) ·
  [JSVirtualMachine](https://developer.apple.com/documentation/javascriptcore/jsvirtualmachine) ·
  [JSContext.isInspectable](https://developer.apple.com/documentation/javascriptcore/jscontext/isinspectable) ·
  [JSContextRefPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextRefPrivate.h)
- JS on iOS: [To JSC or not to JSC (Coote, 2020)](https://dev.to/alastaircoote/to-jsc-or-not-to-jsc-running-javascript-on-ios-in-2020-44ba) ·
  [react-watchos research](https://github.com/emindeniz99/react-watchos/blob/main/docs/research.md) ·
  [react-reconciler](https://github.com/facebook/react/blob/main/packages/react-reconciler/README.md) ·
  [react-native-macos](https://github.com/microsoft/react-native-macos) · [Valdi](https://github.com/Snapchat/valdi) · [LiveView Native](https://github.com/liveview-native)
- App Store climate: [appcompliance.io on 2.5.2 (2026-03-02)](https://appcompliance.io/blog/apple-vibe-coding-crackdown-guideline-2-5-2/) [secondary] ·
  [Obsidian community plugins](https://obsidian.md/help/community-plugins)
- herdr facts: `../multiplexers/herdr.md`.
