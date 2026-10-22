# Icon generator

`build.mjs` writes `../svg/`, `../catalog.json`, `../SOURCES.md`, `../licenses/`, `../contact-sheet.png` and the app's image sets (`Oriel/Assets.xcassets/program.<id>.imageset`), and then checks every SVG (one solid `currentColor` path, renders non-empty, tile contrast >= 3:1).

```sh
mkdir -p /tmp/icons-work/lic && cp package.json /tmp/icons-work/
(cd /tmp/icons-work && npm install)
# License texts that the npm packages do not ship:
curl -sfL -o /tmp/icons-work/lic/lobe.txt  https://raw.githubusercontent.com/lobehub/lobe-icons/master/LICENSE
curl -sfL -o /tmp/icons-work/lic/omp.txt   https://raw.githubusercontent.com/can1357/oh-my-pi/main/LICENSE
curl -sfL -o /tmp/icons-work/lic/aider.txt https://raw.githubusercontent.com/Aider-AI/aider/main/LICENSE.txt
curl -sfL -o /tmp/icons-work/lic/jj.txt    https://raw.githubusercontent.com/jj-vcs/jj/main/LICENSE
node build.mjs   # about 2 minutes
```

Set `ICONS_WORK` to use another folder than `/tmp/icons-work`. `ext/` holds the three marks taken from the programs' own repos (omp, aider, jj).

To change an icon, edit its row in the `E` table (source, brand color, notes) or its shape in `ORIG`, and run the build again.
