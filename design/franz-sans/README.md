# Franz Sans

A plain, highly legible grotesque for web and UI text, the main typeface of
the Franzwerk type system. Franz Antiqua (`../franz-antiqua`) is the accent
face for highlights.

- Weights: Regular 400, Medium 500, Semibold 600, Bold 700
- Large x-height (530 at 710 cap height), open apertures, low stroke contrast
- Distinct I / l / 1 (l has a tail, 1 has a flag)
- Hinted with ttfautohint for crisp rendering on Windows
- 108 glyphs incl. ÄÖÜäöüß, € and kerning
- License: SIL Open Font License 1.1

## Usage

```html
<link rel="stylesheet" href="design/franz-sans/franz-sans.css">
<link rel="stylesheet" href="design/franz-antiqua/franz-antiqua.css">
```

```css
body        { font-family: var(--font-text); }      /* Franz Sans */
.hero-title { font-family: var(--font-highlight); } /* Franz Antiqua, from ~28px */
```

Flutter: registered as `FranzSans` in `pubspec.yaml`.

```dart
Text('Projekte', style: TextStyle(fontFamily: 'FranzSans', fontWeight: FontWeight.w600))
```

## Rebuild

```sh
pip install fonttools skia-pathops brotli ttfautohint-py
python3 build.py
```
