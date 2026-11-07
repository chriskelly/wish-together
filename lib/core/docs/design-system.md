# Design system

Scope: where a brand value lives, how Material slots are pinned from it, and the
three primitives a theme cannot express. Read before changing a colour, the type
scale, or a shared widget's look. Paths are relative to `lib/core/`, then to the
repository root.

`design_tokens.dart` defines `BrandPalette.light` and `BrandPalette.dark` plus the geometry and
type constants. `theme.dart` calls `toColorScheme()` and builds `lightTheme` and `darkTheme` from
one palette each; `lib/main.dart`, the update gate and the dev notice pages pass both to
`MaterialApp`. The theme's slots and component themes are derived in that builder, so a colour or
`ThemeData` field set anywhere else is not carried by the theme.

## Roles and slots

`BrandPalette.light` and `BrandPalette.dark` carry one value per role, and
`toColorScheme()` pins the Material slots those roles resolve through:

| Role | Slot | Used for |
| ---- | ---- | -------- |
| `canvas` | `surfaceContainerLowest`, `scaffoldBackgroundColor` | scaffold and app-bar ground |
| `surface` | `surface`, `surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh` | cards, dialogs, sheets |
| `ink` | `onSurface` | body text, card outline, shadow |
| `inkMuted` | `onSurfaceVariant` | subtitles, available, claimed by someone else, a reader's claimed card text, enabled input borders |
| `primary` | `primary` | hero block, filled buttons, links, progress spinners |
| `onPrimary` | `onPrimary` | text on primary |
| `secondary` | `secondary` | claimed-by-you fill, FAB |
| `onSecondary` | `onSecondary` | text on secondary |
| `outline` | `outline` | the 2px card border |
| `outlineVariant` | `outlineVariant` | dividers, the empty placeholder |
| `error` | `error` | destructive actions |
| `onError` | `onError` | text on error |

`surfaceContainerHighest` is the one step away from `surface` (light
`#F1E8CF`, dark `#2A312B`). `inverseSurface`, `onInverseSurface` and
`inversePrimary` are pinned too, which is what keeps snackbars on-brand.

The enabled outline of a text field uses `inkMuted`, not `outlineVariant`: a
control boundary must reach 3:1 (WCAG 1.4.11), and `outlineVariant` measures
about 1.5:1 against `surface`. An error border keeps `error`, so an invalid
field cannot read as a valid one, and focus stays `primary`. `outlineVariant`
is for dividers and the empty-state box.

Two rules follow from the values:

- **Brass is a fill colour.** `secondary` on `surface` measures about 2.4:1 in
  light, so it must never carry text there. `StatusPill` shows claimed-by-you as
  a brass fill with `onSecondary` text; a brass label would be unreadable.
- **The hard shadow is a light-mode device.** `BrandPalette.shadowOffset` is
  `(4, 4)` in light and `Offset.zero` in dark, because a hard offset on a dark
  ground reads as a smudge. Dark cards keep the 2px outline and drop the offset.
  `BrandCard` reserves the offset as padding so the shadow is not clipped at a
  scroll edge.

To add a role that both brightnesses must change independently and that has no
`ColorScheme` slot, a `ThemeExtension` becomes the right tool. Every role so far
has a slot, so none exists.

## Type

Three faces with a fixed division of labour: Archivo carries text (weight 800,
ExtraBold, for control labels), Archivo Black carries headings, and Pacifico
carries hero titles only; Home and Login are the screens wired to one. A section
header in Pacifico, or a hero title in Archivo Black, breaks the pairing. The
type scale lives in `buildTextTheme`; `labelLarge` is the control label every
button and chip inherits.

The five Latin-subset faces are bundled under `assets/fonts/` (provenance and
regeneration in its `README.md`), so the app's own strings make no font request
on a cold start. Flutter web's engine still fetches its default Roboto once per
page load, and a glyph outside the subset falls back to the engine's fallback
font; both are platform behaviour, not app code. Archivo is instanced into
static 400/700/800 files rather than shipped as a variable font, so ordinary
`fontWeight` selects the right face. `ThemeData.fontFamily` is Archivo for the
roles the table does not list; every style the table defines names its own
family, because the fallback family is applied before the token text theme is
merged.

## How a widget gets its colour

```text
widget's own style                1. call site
  else ThemeData.<component>Theme  2. component theme
    else colorScheme role          3. component default
      else Material constant       4. Flutter fallback
```

That is why a token change restyles screens nobody edited, and why a per-screen
override is only for one call site that must differ from the theme.

## Primitives

Three of the shared widgets are the primitives — `lib/common/widgets/brand_card.dart`,
`lib/common/widgets/brand_hero.dart` and `lib/common/widgets/status_pill.dart` — because a theme cannot express them;
a fourth needs a screen that genuinely cannot be themed.

- `BrandCard(child, margin, backgroundColor)` — a shadow container wrapping a
  `Card` with elevation 0, a 6dp radius and the 2px `outline`. The fill defaults
  to `surfaceContainerLow`; a state that needs another surface step passes
  `backgroundColor` (the wishlist details page uses `surfaceContainerHighest` for
  a reader's claimed item). The inner `Card` keeps ink on a Material surface; a
  bare decorated container would lose `ListTile`'s ink.
- `BrandHero(title, actions, titleStyle)` — the primary block Home and Login use
  in place of an app bar. The title is split on `\n` into explicit lines, each
  scaled down with `FittedBox`, so a long name or a high text scale shrinks the
  glyphs instead of breaking a word. The line never grows past the block, so a
  2.0 text scale is capped on the hero alone. `titleStyle` defaults to
  `displayMedium`; Home passes `heroHomeTextStyle` and Login passes
  `heroLoginTextStyle`, so the face and size are chosen at the call site.
- `StatusPill(label, tone)` — a claim-state badge. `neutral` is outlined with
  muted ink, `accent` is a brass fill with `onSecondary` text. The theme gallery
  previews both tones, and the wishlist details page renders both claim states
  with them.

`PrimaryAppBar(title, actions, leading, automaticallyImplyLeading)` is the bar
the shared feature pages adopt as they are restyled. Its extra slots forward to
`AppBar`, so a bar keeps whatever controls and back-arrow behaviour it had; the
title style and the 2px bottom rule are the only treatment it imposes.
