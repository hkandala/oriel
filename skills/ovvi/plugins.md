# Plugins

A plugin is a package that adds a kind of card to Ovvi. The kinds that come with Ovvi are `browser`,
`explorer` (File Explorer) and `git`.

```sh
ovvi plugins --json                       # id, name, opens, source, version, or the error of one that did not load
ovvi plugins --for ./data.csv             # only the plugins that open it, the default first
```

- `--for` lists the plugins that open the file, folder or URL, best first, with `"default": true` on the one
  that `ovvi open <path>` picks. For a file, the plugins that offer it only in Open With come after them.
  `ovvi open <id> <path>` opens it with any plugin in that list.

## Make a plugin

This works only from a pane on Ovvi's Mac. A remote pane gets `other_machine`.

```sh
ovvi --timeout 300 plugins new "CSV Table" --json    # the template, installed, built and trusted: id, folder, log
# edit the files in the folder, then:
ovvi --timeout 120 plugins reload csv-table --json   # {"id":"csv-table","built":true,"ms":412,"cards":1}
ovvi open csv-table ./data.csv
tail -f <log>                             # the plugin's log
```

- If the build fails, `reload` exits 1 with `build_failed` and prints the last 20 lines of the build. Open cards
  keep running the last good build.
- If a card of the plugin has unsaved edits, `reload` stops with `dirty` and names the pane. Ask the user to
  save. Ovvi never discards edits.
- `new` and `reload` install and build, so pass a long `--timeout`.
- `ovvi plugins reload` with no id reloads every plugin that has an open card.
- `reload <id>` of a plugin the user did not trust yet is `failed`: its card asks the user first.
- The manifest, the API and the template: https://ovvi.dev/docs/plugins/building

## Install a plugin

This works only from a pane on Ovvi's Mac.

```sh
ovvi --timeout 600 plugins install npm:@acme/ovvi-csv     # or git:<url>, or a folder: ./my-plugin, /path
```

- Ovvi asks the user on the Mac to trust it. If the user clicks Cancel, the answer is `declined`.
- The answer comes after the install and the build, so pass a long `--timeout`. Exit 4 means that the wait
  ended and the install goes on. `ovvi plugins` shows the plugin when it is ready.
- The user removes and updates plugins in Ovvi's Plugins panel. A source already installed is `bad_argument`.
