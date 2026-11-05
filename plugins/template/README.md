# My Plugin

A starting point for an Ovvi plugin: a package whose `ovvi` key in `package.json` is its manifest, built from `src/`
into `dist/` by its own `build` script.

In Ovvi, Settings ▸ Plugins ▸ New Plugin… does steps 1 and 2 for you.

1. Copy this folder to `~/.config/ovvi/plugins/<id>/` and set `name` and the `ovvi` key's `id` and `name`.
2. `npm install`, then `npm run build` (or `npm run dev` to build on every save). Ovvi needs Node.js for this.
3. Open a card of it (Open With on a `.txt` file). After an edit, Reload Plugin (⌥⌘R) builds and reloads it.
4. `npm run check` checks the types. Build errors and `console` lines are in
   `~/Library/Logs/Ovvi/plugins/<id>.log` (the card's menu: Show Log).
