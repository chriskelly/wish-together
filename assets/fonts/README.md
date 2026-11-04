# Bundled fonts

Three families, five faces, Latin subset, SIL Open Font License 1.1 (see
`OFL.txt`). Bundling them locally removes the runtime request to
`fonts.gstatic.com` for the app's own strings. A glyph outside the subset falls
back to the engine's/platform's fallback font, which may be fetched.

| File | Family and weight | Flutter `weight` |
| ---- | ----------------- | ---------------- |
| `Archivo-Regular.ttf` | Archivo 400 | 400 (default) |
| `Archivo-Bold.ttf` | Archivo 700 | 700 |
| `Archivo-ExtraBold.ttf` | Archivo 800 | 800 |
| `ArchivoBlack-Regular.ttf` | Archivo Black 400 | 400 (default) |
| `Pacifico-Regular.ttf` | Pacifico 400 | 400 (default) |

Archivo is instanced from the variable font into static weights so ordinary
`fontWeight` selects the right face; the variable file would need `FontVariation`
in every text style.

## Regenerating

Source files are the upstream OFL releases:

- `https://raw.githubusercontent.com/google/fonts/main/ofl/archivo/Archivo%5Bwdth%2Cwght%5D.ttf`
- `https://raw.githubusercontent.com/google/fonts/main/ofl/archivoblack/ArchivoBlack-Regular.ttf`
- `https://raw.githubusercontent.com/google/fonts/main/ofl/pacifico/Pacifico-Regular.ttf`

Run from a scratch directory holding those three files (`Archivo-VF.ttf`,
`ArchivoBlack-Regular.ttf`, `Pacifico-Regular.ttf`), with `fonttools` available
(for example `uvx --from fonttools`):

```sh
fonttools varLib.instancer Archivo-VF.ttf wght=400 --output=Archivo-Regular-full.ttf
fonttools varLib.instancer Archivo-VF.ttf wght=700 --output=Archivo-Bold-full.ttf
fonttools varLib.instancer Archivo-VF.ttf wght=800 --output=Archivo-ExtraBold-full.ttf
cp ArchivoBlack-Regular.ttf ArchivoBlack-Regular-full.ttf
cp Pacifico-Regular.ttf Pacifico-Regular-full.ttf

for f in Archivo-Regular Archivo-Bold Archivo-ExtraBold ArchivoBlack-Regular Pacifico-Regular; do
  pyftsubset "$f-full.ttf" \
    --unicodes="U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-2019,U+201C-201D,U+2026" \
    --layout-features='*' --output-file="$f.ttf"
done
```

The subset covers printable ASCII, Latin-1, en/em dashes, the curly quotes and
the ellipsis. A display name written outside it falls back to the platform font
for those characters; widen the unicode list if that becomes visible in use.
