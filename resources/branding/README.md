# Oriel app icon

The **Flat Graphite Stack**: three front-facing, overlapping rounded
rectangles, stepping down to the right from charcoal to gray to pearl white.

| File | Purpose |
| --- | --- |
| `oriel-flat-stack-original.png` | The original artwork, 1254 × 1254, opaque RGB |
| `oriel-macos-1024.png` | Flattened macOS master, 1024 × 1024 RGBA, rounded tile and transparent margin |
| `../../Oriel/Assets.xcassets/AppIcon.appiconset/` | The app's shipping icon PNGs and catalog manifest |

The catalog path above is relative to this directory. Xcode selects `AppIcon`
in Debug and Release.

## Regenerate

From the repository root, using Python 3 with Pillow installed:

```sh
python3 -m venv .build/icon-venv
.build/icon-venv/bin/pip install Pillow==12.3.0
PATH="$PWD/.build/icon-venv/bin:$PATH" make icons
```

Pillow is an optional authoring dependency. Normal builds use the committed
PNGs and do not run the exporter. The exporter resizes the original with
Lanczos, applies an antialiased rounded tile with a clear margin and a subtle
shadow, and fills only the ten macOS slots in `Contents.json`:

| Points | 1× pixels | 2× pixels |
| --- | --- | --- |
| 16 | 16 | 32 |
| 32 | 32 | 64 |
| 128 | 128 | 256 |
| 256 | 256 | 512 |
| 512 | 512 | 1024 |

These are static raster asset-catalog icons, not a layered Liquid Glass
`.icon` file. The rounded tile is baked into the macOS exports; keep the
original square image when creating Icon Composer layers, where the system
supplies the mask. See Apple's [asset catalog guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
and [Icon Composer](https://developer.apple.com/icon-composer/).

Similar stacked-card marks exist (FeedSquad, Interleave); none matches this one.
