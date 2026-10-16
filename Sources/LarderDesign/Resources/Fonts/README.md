# Bundled fonts

`LarderFont.registerBundledFonts()` registers every `.ttf` and `.otf` in the LarderDesign resource bundle for the process. The app calls it in `LarderApp.init()` and the widget extension in `LarderWidgetBundle.init()`, both before the first view renders; each target gets these files through its own copy of the LarderDesign resource bundle. If registration finds no files, Larder falls back to the system serif (display) and the system monospaced face (stamps).

## What is bundled

| File | Used for | PostScript name |
|---|---|---|
| `Fraunces144pt-SoftMedium.ttf` | `largeTitle` | `Fraunces144pt-SoftMedium` |
| `Fraunces144pt-SoftBold.ttf` | `title` | `Fraunces144pt-SoftBold` |
| `Fraunces72pt-SoftSemiBold.ttf` | `title2` and smaller display | `Fraunces72pt-SoftSemiBold` |
| `CommitMono-400-Regular.otf` | stamps, quantities, dates | `CommitMono-Regular` |
| `Fraunces-OFL.txt` | Fraunces licence, unchanged | |
| `CommitMono-OFL.txt` | Commit Mono licence (`license.txt` in the release), unchanged | |

The code selects fonts by PostScript name, so the names above must match `LarderFont`. `FontRegistrationTests` registers the files and checks that every name `LarderFont` asks for resolves to that exact font.

## How the Fraunces statics were made

Source: the Fraunces variable font `Fraunces[SOFT,WONK,opsz,wght].ttf`, version 1.000 (`[b76b70a41]` in its name table), axes opsz 9 to 144, wght 100 to 900, SOFT 0 to 100, WONK 0 to 1. SwiftUI cannot pick arbitrary variable weights, so each display style gets an upright static instance with every axis pinned, cut with fontTools 4.67:

```
fonttools varLib.instancer "Fraunces[SOFT,WONK,opsz,wght].ttf" opsz=144 SOFT=100 WONK=0 wght=500 -o Fraunces144pt-SoftMedium.ttf
fonttools varLib.instancer "Fraunces[SOFT,WONK,opsz,wght].ttf" opsz=144 SOFT=100 WONK=0 wght=700 -o Fraunces144pt-SoftBold.ttf
fonttools varLib.instancer "Fraunces[SOFT,WONK,opsz,wght].ttf" opsz=72 SOFT=100 WONK=0 wght=600 -o Fraunces72pt-SoftSemiBold.ttf
python -I Tools/name-fraunces-statics.py Fraunces144pt-SoftMedium.ttf Fraunces144pt-SoftBold.ttf Fraunces72pt-SoftSemiBold.ttf
```

The instancer leaves the variable font's names behind. `Tools/name-fraunces-statics.py` drops the STAT table and the family, axis and instance names, keeps copyright, version and licence, and sets family, subfamily, full name, unique ID, PostScript name, typographic family and subfamily (for example `Fraunces 144pt Soft` / `Medium`), the OS/2 weight class and the bold and regular style bits. Check the result with:

```
python -I -c "import sys; from fontTools.ttLib import TTFont; [print(p, TTFont(p)['name'].getDebugName(6)) for p in sys.argv[1:]]" *.ttf *.otf
```

Use upright instances only, weights 500 to 700, WONK off; never italic, never light.

Commit Mono is the 1.143 release's `CommitMono-400-Regular.otf`, byte for byte.

## Licences and sources

- Fraunces: SIL Open Font Licence 1.1, copyright 2018 The Fraunces Project Authors. https://github.com/undercasetype/Fraunces
- Commit Mono: SIL Open Font Licence 1.1, copyright 2023 Commit Mono authors. https://commitmono.com (releases at https://github.com/eigilnikolajsen/commit-mono)

The OFL permits bundling and modified instances, but a modified font must not use a Reserved Font Name. Neither licence declares one: the copyright lines in `Fraunces-OFL.txt` and `CommitMono-OFL.txt` carry no "with Reserved Font Name" clause. The cut Fraunces instances therefore keep the Fraunces name. Re-check this if either licence file is ever replaced, and keep both licence files next to the fonts so they ship in the bundle.
