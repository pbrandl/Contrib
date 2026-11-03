# Franz Antiqua

A high-contrast Didone display face for headlines on the web: thick vertical
stems, hairline horizontals, unbracketed hairline serifs and ball terminals.

- Weights: Light (300), Regular (400)
- 101 glyphs: A–Z, a–z, 0–9, ÄÖÜäöüß, é è à É, punctuation incl. „ “ ” ‘ ’, € & + = * /
- Kerning for the common capital/lowercase pairs
- UPM 1000 · cap height 700 · x-height 450
- License: SIL Open Font License 1.1

Use it from about 28 px upward and pair it with Inter for body text.

## Files

| File | Purpose |
| --- | --- |
| `fonts/*.woff2` | web fonts |
| `fonts/*.ttf` | desktop / Flutter |
| `franz-antiqua.css` | `@font-face` rules |
| `specimen.html` | type specimen (open in a browser) |
| `build.py` | parametric source; regenerates all fonts |

## Rebuild

```sh
pip install fonttools skia-pathops brotli
python3 build.py
```

## Flutter

The TTFs are also copied to `/fonts` and registered as `FranzAntiqua` in
`pubspec.yaml`:

```dart
Text('Willkommen', style: TextStyle(fontFamily: 'FranzAntiqua', fontSize: 40))
```
