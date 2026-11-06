// File: the card's file in CodeMirror with its language's colors, and the breadcrumbs `repo › … › file › {} symbol`.
import { StreamLanguage, type StreamParser, syntaxTree } from "@codemirror/language"
import { Compartment, type EditorState, type Extension, RangeSetBuilder } from "@codemirror/state"
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view"
import type { SyntaxNode } from "@lezer/common"
import { code, editor } from "./editor"
import { choose, name, own, type Place, type Reveal } from "./place"

const legacy = (parser: Promise<StreamParser<unknown>>) => parser.then((p) => StreamLanguage.define(p))

/** By extension (or name, for dotfiles); each loads on first use. */
const languages: Record<string, () => Promise<Extension>> = {
  swift: () => legacy(import("@codemirror/legacy-modes/mode/swift").then((m) => m.swift)),
  ts: () => import("@codemirror/lang-javascript").then((m) => m.javascript({ typescript: true })),
  tsx: () => import("@codemirror/lang-javascript").then((m) => m.javascript({ typescript: true, jsx: true })),
  js: () => import("@codemirror/lang-javascript").then((m) => m.javascript({ jsx: true })),
  py: () => import("@codemirror/lang-python").then((m) => m.python()),
  go: () => import("@codemirror/lang-go").then((m) => m.go()),
  rs: () => import("@codemirror/lang-rust").then((m) => m.rust()),
  cpp: () => import("@codemirror/lang-cpp").then((m) => m.cpp()),
  java: () => import("@codemirror/lang-java").then((m) => m.java()),
  kt: () => legacy(import("@codemirror/legacy-modes/mode/clike").then((m) => m.kotlin)),
  rb: () => legacy(import("@codemirror/legacy-modes/mode/ruby").then((m) => m.ruby)),
  sh: () => legacy(import("@codemirror/legacy-modes/mode/shell").then((m) => m.shell)),
  json: () => import("@codemirror/lang-json").then((m) => m.json()),
  yaml: () => import("@codemirror/lang-yaml").then((m) => m.yaml()),
  toml: () => legacy(import("@codemirror/legacy-modes/mode/toml").then((m) => m.toml)),
  html: () => import("@codemirror/lang-html").then((m) => m.html()),
  css: () => import("@codemirror/lang-css").then((m) => m.css()),
}
const aliases: Record<string, string> = {
  mts: "ts", cts: "ts", mjs: "js", cjs: "js", jsx: "js", pyi: "py", c: "cpp", h: "cpp", cc: "cpp", cxx: "cpp",
  hpp: "cpp", hh: "cpp", m: "cpp", mm: "cpp", kts: "kt", rake: "rb", gemspec: "rb", bash: "sh", zsh: "sh",
  zshrc: "sh", bashrc: "sh", profile: "sh", jsonc: "json", yml: "yaml", htm: "html",
}
/** The file's language, by its extension, or its name for a dotfile, a Gemfile or a Rakefile. */
const language = (path: string) => {
  const file = name(path), ext = file.includes(".") ? (file.split(".").pop() ?? "").toLowerCase() : file
  const key = aliases[ext] ?? (ext === "Gemfile" || ext === "Rakefile" ? "rb" : ext)
  return languages[key]?.() ?? []
}

/** Nodes that name a scope in the spec's Lezer grammars, and the nodes that hold their names. */
const scopes = new Set([
  ...["Function", "Class", "Method", "Interface", "Enum", "TypeAlias", "Namespace", "Constructor", "Record"].map(
    (s) => `${s}Declaration`,
  ),
  ...["Function", "Class", "Namespace"].map((s) => `${s}Definition`),
  ...["Function", "Struct", "Enum", "Trait", "Impl", "Mod", "Union"].map((s) => `${s}Item`),
  ...["Class", "Struct", "Enum", "Union"].map((s) => `${s}Specifier`),
  ...["FunctionDecl", "TypeSpec", "Property", "Pair", "RuleSet"],
])
const names =
  /^((Variable|Property|Type)Definition|VariableName|DefName|FieldName|BoundIdentifier|TypeIdentifier|Identifier|FieldIdentifier|ScopedIdentifier|NamespaceIdentifier|DestructorName|Definition|PropertyName|Key)$/

const named = (node: SyntaxNode, state: EditorState): string | undefined => {
  if (node.name === "RuleSet") return node.firstChild ? state.sliceDoc(node.firstChild.from, node.firstChild.to) : undefined
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (names.test(child.name)) return state.sliceDoc(child.from, child.to).replace(/^["']|["']$/g, "")
    // C and C++ name a function inside its declarator.
    if (child.name.endsWith("Declarator")) return named(child, state)
  }
}

/** The legacy modes (Swift, Kotlin, Ruby, shell, TOML) make no tree: the declarations less indented above the caret. */
const declaration =
  /^\s*(?:[\w@]+\s+)*?(?:func|class|struct|enum|protocol|extension|actor|fun|object|interface|def|module|function)\s+([\w.]+)|^\s*([\w-]+)\s*\(\)\s*\{/
const indented = (state: EditorState) => {
  const found: string[] = []
  let limit = Number.POSITIVE_INFINITY
  const caret = state.doc.lineAt(state.selection.main.head).number
  for (let n = caret; n >= 1 && n > caret - 5000 && limit > 0; n--) {
    const text = state.doc.line(n).text, indent = text.search(/\S/)
    if (indent < 0 || indent >= limit) continue
    limit = indent
    const match = declaration.exec(text)
    if (match) found.unshift(match[1] ?? match[2])
  }
  return found
}

/** The scopes around the caret, outermost first. */
const symbol = (state: EditorState) => {
  const found: string[] = []
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(state.selection.main.head, -1); node; node =
    node.parent) {
    const name = scopes.has(node.name) ? named(node, state) : undefined
    if (name) found.unshift(name.trim().slice(0, 80))
  }
  return (found.length ? found : indented(state)).join(" › ")
}

/** Cards are often narrow: lines wrap, and a wrapped line goes on at its own indent, as in Xcode. */
const indents = (view: EditorView) => {
  const builder = new RangeSetBuilder<Decoration>()
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = view.state.doc.lineAt(pos)
      const indent = /^[ \t]*/.exec(line.text)?.[0].replace(/\t/g, " ".repeat(view.state.tabSize)).length ?? 0
      if (indent) {
        const style = `padding-left: calc(${indent}ch + 6px); text-indent: -${indent}ch`
        builder.add(line.from, line.from, Decoration.line({ attributes: { style } }))
      }
      pos = line.to + 1
    }
  }
  return builder.finish()
}
const hanging = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet
    constructor(view: EditorView) {
      this.decorations = indents(view)
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.viewportChanged) this.decorations = indents(update.view)
    }
  },
  { decorations: (plugin) => plugin.decorations },
)

export async function show(place: Place): Promise<Reveal> {
  const { ovvi, arg, trail } = place
  /** The breadcrumbs, then the scopes around the caret after `{}`. */
  const jump = (scope: string) =>
    ovvi.controls.set("jump", { value: [...trail, ...(scope ? [scope] : [])], symbol: scope ? "curlybraces" : "" })
  let last = ""
  /** Word Wrap, on until the card turns it off: cards are often narrow. */
  const wrap = new Compartment(), wrapped = (on: boolean) => (on ? [EditorView.lineWrapping, hanging] : [])
  let on = own(ovvi).wrap ?? true
  ovvi.controls.set("wrap", { value: on })
  const shown = await editor(place, [
    code,
    wrap.of(wrapped(on)),
    await language(arg),
    EditorView.updateListener.of((update) => {
      const now = symbol(update.state)
      if (now !== last) jump((last = now))
    }),
  ], place.root)
  const view = shown?.view
  // The info view has no lines to wrap.
  if (!view) return void ovvi.controls.set("wrap", { hidden: true })
  const rewrap = (now: boolean) => {
    if (now === on) return
    on = now
    ovvi.controls.set("wrap", { value: on })
    // The line at the top stays in place.
    const top = view.lineBlockAtHeight(view.scrollDOM.scrollTop - view.documentPadding.top).from
    view.dispatch({ effects: [wrap.reconfigure(wrapped(on)), EditorView.scrollIntoView(top, { y: "start" })] })
  }
  ovvi.on("control", ({ id, value }) => {
    if (id !== "wrap") return
    choose(ovvi, { wrap: value === true })
    rewrap(value === true)
  })
  // A kept page shown again takes the card's choice from another file's page, and so does this one if another
  // changed it while this one drew.
  ovvi.on("place", () => rewrap(own(ovvi).wrap ?? true))
  rewrap(own(ovvi).wrap ?? true)
  return shown.land
}
