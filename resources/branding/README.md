# Oriel app icon

The approved **Flat Graphite Stack**: three front-facing, overlapping rounded
rectangles, stepping down to the right from charcoal to gray to pearl white.
The original artwork is preserved without alteration.

| File | Purpose |
| --- | --- |
| `oriel-flat-stack-original.png` | Original approved generated image, 1254 × 1254, opaque RGB |
| `oriel-macos-1024.png` | Flattened macOS master, 1024 × 1024 RGBA, rounded tile and transparent margin |
| `Oriel.icns` | Standalone export containing all ten macOS 1×/2× representations |
| `../../Oriel/Assets.xcassets/AppIcon.appiconset/` | The app's shipping icon PNGs and catalog manifest |

The catalog path above is relative to this directory. Xcode already selects
`AppIcon` in both Debug and Release and discovers the asset catalog through
the synchronized app group. No project-file or runtime icon override is needed.
The existing iOS appearance placeholders are unchanged; these exports target macOS.

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

The standalone ICNS contains the same PNG representations. On a Mac, they can
also be copied to an `Oriel.iconset` directory and packed with
`iconutil -c icns Oriel.iconset`.

These are static raster asset-catalog icons, not a layered Liquid Glass
`.icon` file. The rounded tile is baked into the macOS exports; keep the
original square image when creating Icon Composer layers, where the system
supplies the mask. See Apple's [asset catalog guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
and [Icon Composer](https://developer.apple.com/icon-composer/).

## Similarity screening — 26 October 2026

The approved original was uploaded to Google Lens. Its **Exact matches** view
reported **No exact matches found**. The initial visual matches primarily
showed unrelated rectangular physical products. A follow-up narrowed to
`app logo` hit Google's unusual-traffic verification, so that refinement was
not completed. This is a limited visual screen, not an exhaustive search or
a trademark clearance; no claim of exclusive ownership of the stacked-card
motif is implied.

A separate keyword image search found related motifs, including these two
examples whose artwork was inspected on their own sites:

- [FeedSquad brand kit](https://feedsquad.com/brand-kit): three rounded square
  cards offset down to the **left**, with blue accents. Oriel uses wider
  landscape panes offset down to the **right**, neutral tones and dark gutters.
- [Interleave](https://interleave.app/) ([logo](https://interleave.app/assets/logo.png)):
  three blue upright panes in perspective. Oriel's landscape panes face front
  and have different proportions, spacing, direction and coloring.

The shared idea is similar; neither inspected artwork is an exact visual
match for the approved Oriel image. Search results cannot establish legal
availability or guarantee that no closer mark exists.
