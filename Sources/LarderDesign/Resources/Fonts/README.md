# Bundled fonts

No font binaries are committed. `LarderFont.registerBundledFonts()` registers every `.ttf` and `.otf` found in this folder at launch. Until the files are present, Larder falls back to the system serif (display) and the system monospaced face (stamps), and nothing else changes.

## Files to drop in

| File | Used for | PostScript name |
|---|---|---|
| `Fraunces144pt-SoftMedium.ttf` | `largeTitle` | `Fraunces144pt-SoftMedium` |
| `Fraunces144pt-SoftBold.ttf` | `title` | `Fraunces144pt-SoftBold` |
| `Fraunces72pt-SoftSemiBold.ttf` | `title2` and smaller display | `Fraunces72pt-SoftSemiBold` |
| `CommitMono-400-Regular.otf` | stamps, quantities, dates | `CommitMono-400Regular` |

The PostScript name inside each file must match the table, because the code selects fonts by that name. Check with `fc-scan --format '%{postscriptname}\n' <file>`.

## Making the Fraunces statics

Fraunces ships as a variable font with axes weight, optical size (opsz 9 to 144), SOFT and WONK. SwiftUI cannot pick arbitrary variable weights, so cut upright static instances with fontTools:

```
fonttools varLib.instancer Fraunces[SOFT,WONK,opsz,wght].ttf opsz=144 SOFT=100 WONK=0 wght=500 -o Fraunces144pt-SoftMedium.ttf
fonttools varLib.instancer Fraunces[SOFT,WONK,opsz,wght].ttf opsz=144 SOFT=100 WONK=0 wght=700 -o Fraunces144pt-SoftBold.ttf
fonttools varLib.instancer Fraunces[SOFT,WONK,opsz,wght].ttf opsz=72 SOFT=100 WONK=0 wght=600 -o Fraunces72pt-SoftSemiBold.ttf
```

Set the name table (family, subfamily, PostScript name) on each output to match the table above. Use upright instances only, weights 500 to 700; never italic, never light.

## Licences and sources

- Fraunces: SIL Open Font Licence 1.1. https://github.com/undercasetype/Fraunces
- Commit Mono: SIL Open Font Licence 1.1. https://commitmono.com (releases at https://github.com/eigilnikolajsen/commit-mono)

The OFL permits bundling and modified instances, but a modified font must not use a Reserved Font Name. Check the licence file shipped with each family and keep it next to the font files.
