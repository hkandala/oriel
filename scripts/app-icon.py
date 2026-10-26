#!/usr/bin/env python3
"""Export Oriel's approved artwork to its macOS asset catalog and an ICNS."""

import io
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "resources/branding"
CATALOG = ROOT / "Oriel/Assets.xcassets/AppIcon.appiconset"
SLOTS = (
    (16, 1, b"icp4"), (16, 2, b"ic11"),
    (32, 1, b"icp5"), (32, 2, b"ic12"),
    (128, 1, b"ic07"), (128, 2, b"ic13"),
    (256, 1, b"ic08"), (256, 2, b"ic14"),
    (512, 1, b"ic09"), (512, 2, b"ic10"),
)


def main():
    with Image.open(BRAND / "oriel-flat-stack-original.png") as source:
        if source.width != source.height or source.width < 1024:
            raise ValueError("The source must be square and at least 1024 pixels wide")
        artwork = source.convert("RGB").resize((832, 832), Image.Resampling.LANCZOS)

    # A flattened macOS asset-catalog icon needs its own rounded tile and clear margin.
    # Keep the approved artwork intact within it; this is not an Icon Composer layer.
    mask = Image.new("L", (832 * 4, 832 * 4))
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1), radius=184 * 4, fill=255
    )
    mask = mask.resize((832, 832), Image.Resampling.LANCZOS)
    tile = artwork.convert("RGBA")
    tile.putalpha(mask)

    shadow = Image.new("RGBA", (1024, 1024))
    shadow_mask = Image.new("L", shadow.size)
    shadow_mask.paste(mask, (96, 106))
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(10)).point(lambda a: a // 4))
    master = Image.new("RGBA", (1024, 1024))
    master.alpha_composite(shadow)
    master.alpha_composite(tile, (96, 96))
    master.save(BRAND / "oriel-macos-1024.png", optimize=True)

    # The iOS target builds from the same catalog: one opaque 1024 px square, unmasked (iOS rounds it).
    artwork_ios = Image.open(BRAND / "oriel-flat-stack-original.png").convert("RGB")
    artwork_ios.resize((1024, 1024), Image.Resampling.LANCZOS).save(CATALOG / "icon_ios_1024.png", optimize=True)

    contents = json.loads((CATALOG / "Contents.json").read_text())
    for entry in contents["images"]:
        if entry.get("platform") == "ios" and "appearances" not in entry:
            entry["filename"] = "icon_ios_1024.png"
    entries = {(e["size"], e["scale"]): e for e in contents["images"] if e["idiom"] == "mac"}
    icns = bytearray()
    for points, scale, kind in SLOTS:
        pixels = points * scale
        suffix = "@2x" if scale == 2 else ""
        name = f"icon_{points}x{points}{suffix}.png"
        icon = master.resize((pixels, pixels), Image.Resampling.LANCZOS)
        icon.save(CATALOG / name, optimize=True)
        entries[(f"{points}x{points}", f"{scale}x")]["filename"] = name
        with io.BytesIO() as stream:
            icon.save(stream, "PNG", optimize=True)
            data = stream.getvalue()
        icns.extend(kind + struct.pack(">I", len(data) + 8) + data)

    (CATALOG / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    (BRAND / "Oriel.icns").write_bytes(b"icns" + struct.pack(">I", len(icns) + 8) + icns)
    print("Exported 10 macOS PNG slots (16–1024 px), the master and Oriel.icns")


if __name__ == "__main__":
    main()
