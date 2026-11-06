# App icons

Scope: how every platform icon is generated from one source, and how to verify
it. Read before touching `web/favicon.png`, an app icon, or an icon build step.

The single source is `web/favicon.png` (1024×1024, **opaque**, cream ground `#FFFCF0`,
cranberry mark `#B32234`). Every platform icon comes from it, resized with `sips`, and must
stay opaque at its exact pixel size: the App Store rejects an icon with a transparency
channel.

- **iOS:** fifteen PNGs in `ios/Runner/Assets.xcassets/AppIcon.appiconset/` cover the nineteen
  entries in its Contents.json, because four iPad entries reuse an iPhone filename, so do not expect
  one file per entry. Each file is `points × scale` pixels, so `29x29@2x` is 58 px and is made
  with `sips -z 58 58 web/favicon.png --out <file>`; the 1024 marketing icon is a byte copy of
  the source.
- **Web:** `web/icons/` holds 192 and 512, and each maskable file is a byte copy of its
  non-maskable twin (`cp web/icons/Icon-192.png web/icons/Icon-maskable-192.png`, likewise
  512). The mark's farthest ink sits 37.3% of the icon width from the centre, inside the 40%
  radius of the maskable safe circle, so the pair needs no extra padding and no separate
  composition step.
- **Web manifest:** `web/manifest.json` keeps the icon paths; `background_color` is `#F6F0DC`,
  a deliberately warmer, slightly darker cream than the icon's ground, and `theme_color` is the
  cranberry `#B32234`.
- **Android:** five legacy `mipmap-*/ic_launcher.png` (48 to 192) plus the adaptive icon in
  `mipmap-anydpi-v26/ic_launcher.xml`. Its foreground is the source centred on the same cream,
  in two passes: `sips -z <inner> <inner> web/favicon.png --out /tmp/fg.png`, then
  `sips --padToHeightWidth <layer> <layer> --padColor FFFCF0 /tmp/fg.png --out <file>`
  (`--padToHeightWidth` must come before `--padColor`, and padding in the same `sips` call as
  the resize gives identical pixels but different PNG bytes). The inner/layer pairs are
  88/108, 132/162, 176/216, 264/324 and 352/432 px, one per density bucket, each writing
  `mipmap-*/ic_launcher_foreground.png`; using the mdpi pair for a larger bucket silently ships
  an upscaled icon. That keeps the solid artwork about 65 dp across, inside the 66 dp safe
  circle launchers guarantee, while the outer 18 dp of each 108 dp layer may be cropped. The
  background layer is `@color/ic_launcher_background` in
  `android/app/src/main/res/values/ic_launcher_background.xml`, also `#FFFCF0`.
- **Verify:** run `sips -g pixelWidth -g pixelHeight -g hasAlpha` over every PNG under
  `web/`, the iOS set and `android/app/src/main/res/mipmap-*`; every file must report
  `hasAlpha: no` at the size its
  `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` entry, density bucket
  or inner/layer pair names.
