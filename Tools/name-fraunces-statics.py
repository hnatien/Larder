#!/usr/bin/env python3
"""Set the name table and style bits on Fraunces static instances cut with fontTools' instancer.

Run with a Python that has fontTools, for example:
    python -I Tools/name-fraunces-statics.py Fraunces144pt-SoftMedium.ttf Fraunces144pt-SoftBold.ttf Fraunces72pt-SoftSemiBold.ttf

Each file is identified by its file name (the PostScript name plus .ttf) and rewritten in place.
See Sources/LarderDesign/Resources/Fonts/README.md for the instancer commands that come first.
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

# PostScript name: (typographic family, typographic subfamily, OS/2 weight class)
INSTANCES = {
    "Fraunces144pt-SoftMedium": ("Fraunces 144pt Soft", "Medium", 500),
    "Fraunces144pt-SoftBold": ("Fraunces 144pt Soft", "Bold", 700),
    "Fraunces72pt-SoftSemiBold": ("Fraunces 72pt Soft", "SemiBold", 600),
}

WINDOWS = (3, 1, 0x409)
FS_ITALIC, FS_BOLD, FS_REGULAR = 1 << 0, 1 << 5, 1 << 6


def rename(path: Path) -> None:
    postscript = path.stem
    if postscript not in INSTANCES:
        sys.exit(f"{path.name}: not one of {', '.join(INSTANCES)}")
    family, style, weight = INSTANCES[postscript]
    font = TTFont(path)
    if "fvar" in font:
        sys.exit(f"{path.name}: still variable; pin every axis with the instancer first")

    bold = style == "Bold"
    # Legacy family/subfamily (IDs 1 and 2) only know Regular and Bold, so other weights carry their own family.
    legacy_family = family if bold else f"{family} {style}"
    legacy_style = "Bold" if bold else "Regular"
    full = f"{family} {style}"
    version = font["name"].getDebugName(5) or "Version 1.000"

    # A single static instance needs no style attributes; STAT would also point at the axis names dropped below.
    if "STAT" in font:
        del font["STAT"]
    table = font["name"]
    # Keep copyright, version, credits and licence; drop the variable font's family, axis and instance names.
    keep = {0, 5, 7, 8, 9, 11, 12, 13, 14}
    table.names = [record for record in table.names if record.nameID in keep]
    values = {
        1: legacy_family,
        2: legacy_style,
        3: f"{version.removeprefix('Version ').split(';')[0]};UCT;{postscript}",
        4: full,
        6: postscript,
        16: family,
        17: style,
    }
    for name_id, value in values.items():
        table.setName(value, name_id, *WINDOWS)

    os2 = font["OS/2"]
    os2.usWeightClass = weight
    selection = os2.fsSelection & ~(FS_ITALIC | FS_BOLD | FS_REGULAR)
    os2.fsSelection = selection | (FS_BOLD if bold else FS_REGULAR)
    font["head"].macStyle = 1 if bold else 0
    font["post"].italicAngle = 0
    font.save(path)
    print(f"{path.name}: {postscript} ({full}, weight {weight})")


def main(paths: list[str]) -> None:
    if not paths:
        sys.exit(__doc__)
    for path in paths:
        rename(Path(path))


if __name__ == "__main__":
    main(sys.argv[1:])
