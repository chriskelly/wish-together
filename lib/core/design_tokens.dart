import 'package:flutter/material.dart';

/// The three bundled typefaces. `Archivo` carries text, `Archivo Black` carries
/// headings, `Pacifico` carries hero titles.
const String archivoFamily = 'Archivo';
const String archivoBlackFamily = 'Archivo Black';
const String pacificoFamily = 'Pacifico';

/// A deliberate no-fill (`surfaceTintColor`, for example). It lives here so the
/// colour-literal gate can scan all of `lib/` except this file and `lib/dev/`.
const Color brandTransparent = Color(0x00000000);

/// Brand values for one brightness.
///
/// This is the only place a Holly & Brass colour is written. Everything
/// downstream resolves through [toColorScheme] or a `ThemeData` built from it.
@immutable
class BrandPalette {
  const BrandPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.inkMuted,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.outline,
    required this.outlineVariant,
    required this.error,
    required this.onError,
    required this.surfaceContainerHighest,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.shadowOffset,
  });

  final Brightness brightness;

  /// Scaffold and app-bar ground.
  final Color canvas;

  /// Cards, dialogs and sheets.
  final Color surface;

  /// Body text, card outline and shadow.
  final Color ink;

  /// Subtitles, secondary labels and claim text the viewer does not own.
  final Color inkMuted;

  /// Hero block, filled buttons and links.
  final Color primary;
  final Color onPrimary;

  /// Claimed-by-you fill and the floating action button. Brass is a fill
  /// colour: on the light ground it is about 2.4:1 against [surface], so it
  /// must never be used for text there.
  final Color secondary;
  final Color onSecondary;

  final Color outline;
  final Color outlineVariant;
  final Color error;
  final Color onError;

  /// The one surface step that differs from [surface] within a palette.
  final Color surfaceContainerHighest;

  final Color shadow;
  final Color scrim;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;

  /// The hard offset behind a card. Zero in dark: on a dark ground it reads as
  /// a smudge, so dark cards keep the outline and drop the offset.
  final Offset shadowOffset;

  static const BrandPalette light = BrandPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFF6F0DC),
    surface: Color(0xFFFFFCF0),
    ink: Color(0xFF12251A),
    inkMuted: Color(0xFF5C6B5F),
    primary: Color(0xFFB32234),
    onPrimary: Color(0xFFFFFCF0),
    secondary: Color(0xFFC8992E),
    onSecondary: Color(0xFF12251A),
    outline: Color(0xFF12251A),
    outlineVariant: Color(0xFFD8CFB4),
    error: Color(0xFF981B27),
    onError: Color(0xFFFFFCF0),
    surfaceContainerHighest: Color(0xFFF1E8CF),
    shadow: Color(0xFF12251A),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF12251A),
    onInverseSurface: Color(0xFFF6F0DC),
    inversePrimary: Color(0xFFE2707C),
    shadowOffset: Offset(4, 4),
  );

  static const BrandPalette dark = BrandPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF161B17),
    surface: Color(0xFF1E241F),
    ink: Color(0xFFF3EDDC),
    inkMuted: Color(0xFFA9B0A4),
    primary: Color(0xFFE2707C),
    onPrimary: Color(0xFF2A0E12),
    secondary: Color(0xFFD9AE4B),
    onSecondary: Color(0xFF241C08),
    outline: Color(0xFFC9C2AE),
    outlineVariant: Color(0xFF3A4238),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3B0910),
    surfaceContainerHighest: Color(0xFF2A312B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF3EDDC),
    onInverseSurface: Color(0xFF161B17),
    inversePrimary: Color(0xFFB32234),
    shadowOffset: Offset.zero,
  );

  /// The palette that matches [context]'s brightness.
  static BrandPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;

  /// The Material slots the app resolves through.
  ///
  /// Slots outside this map keep the constructor defaults Material picks, which
  /// is why the container roles are pinned rather than left to `fromSeed`.
  ColorScheme toColorScheme() => ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    secondary: secondary,
    onSecondary: onSecondary,
    error: error,
    onError: onError,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: inkMuted,
    outline: outline,
    outlineVariant: outlineVariant,
    shadow: shadow,
    scrim: scrim,
    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
    inversePrimary: inversePrimary,
    surfaceContainerLowest: canvas,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    surfaceContainerHighest: surfaceContainerHighest,
  );
}

/// Spacing, corner and border values shared by both brightnesses.
abstract final class BrandGeometry {
  static const double radius = 6;
  static const double borderWidth = 2;
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;

  /// Between two top-level data sections on a page.
  static const double sectionGap = 30;

  /// The vertical breathing room a card carries for its hard shadow.
  static const double cardMarginVertical = 7;

  /// The one corner radius, for every rounded surface.
  static const BorderRadius corners = BorderRadius.all(Radius.circular(radius));
}

/// Home's hero title: Pacifico, because the greeting should read as a greeting
/// rather than a heading.
const TextStyle heroHomeTextStyle = TextStyle(
  fontFamily: pacificoFamily,
  fontSize: 38,
  height: 1.15,
  fontWeight: FontWeight.w400,
);

/// Login's hero title, one size up because it is the product name.
const TextStyle heroLoginTextStyle = TextStyle(
  fontFamily: pacificoFamily,
  fontSize: 50,
  height: 1.25,
  fontWeight: FontWeight.w400,
);

/// The text roles every screen inherits. Each style names its own family:
/// `ThemeData.fontFamily` only covers the roles this table does not list.
TextTheme buildTextTheme(BrandPalette palette) => TextTheme(
  displayLarge: TextStyle(
    fontFamily: archivoBlackFamily,
    fontSize: 46,
    height: 1.02,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.0,
    color: palette.ink,
  ),
  displayMedium: TextStyle(
    fontFamily: archivoBlackFamily,
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.8,
    color: palette.ink,
  ),
  headlineMedium: TextStyle(
    fontFamily: archivoBlackFamily,
    fontSize: 27,
    height: 1.10,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.5,
    color: palette.ink,
  ),
  headlineSmall: TextStyle(
    fontFamily: archivoBlackFamily,
    fontSize: 21,
    height: 1.15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    color: palette.ink,
  ),
  titleLarge: TextStyle(
    fontFamily: archivoBlackFamily,
    fontSize: 19,
    height: 1.20,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: palette.ink,
  ),
  titleMedium: TextStyle(
    fontFamily: archivoFamily,
    fontSize: 16,
    height: 1.30,
    fontWeight: FontWeight.w700,
    color: palette.ink,
  ),
  bodyLarge: TextStyle(
    fontFamily: archivoFamily,
    fontSize: 16,
    height: 1.50,
    fontWeight: FontWeight.w400,
    color: palette.ink,
  ),
  bodyMedium: TextStyle(
    fontFamily: archivoFamily,
    fontSize: 14.5,
    height: 1.50,
    fontWeight: FontWeight.w400,
    color: palette.ink,
  ),
  bodySmall: TextStyle(
    fontFamily: archivoFamily,
    fontSize: 12.5,
    height: 1.40,
    fontWeight: FontWeight.w400,
    color: palette.inkMuted,
  ),
  labelLarge: TextStyle(
    fontFamily: archivoFamily,
    fontSize: 13,
    height: 1.40,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    color: palette.ink,
  ),
);

/// A list row title: Archivo ExtraBold, 17.
TextStyle listTileTitleStyle(BrandPalette palette) => TextStyle(
  fontFamily: archivoFamily,
  fontSize: 17,
  fontWeight: FontWeight.w800,
  color: palette.ink,
);

/// A list row subtitle: Archivo 400, 13.5, muted.
TextStyle listTileSubtitleStyle(BrandPalette palette) => TextStyle(
  fontFamily: archivoFamily,
  fontSize: 13.5,
  fontWeight: FontWeight.w400,
  color: palette.inkMuted,
);
