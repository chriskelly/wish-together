import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The light and dark themes are built from [BrandPalette], so a brand change
/// touches `design_tokens.dart` and nothing else.
///
/// `lightTheme` and `darkTheme` are the only theme entry points: `main.dart`,
/// the update gate and the dev shell all pass both to `MaterialApp`.
final ThemeData lightTheme = _buildTheme(BrandPalette.light);

final ThemeData darkTheme = _buildTheme(BrandPalette.dark);

ThemeData _buildTheme(BrandPalette palette) {
  final scheme = palette.toColorScheme();
  final textTheme = buildTextTheme(palette);

  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.canvas,
    // Covers the roles the token table does not list, including styles Material
    // components build for themselves. Every listed style names its own family.
    fontFamily: archivoFamily,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: palette.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      surfaceTintColor: brandTransparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.headlineSmall,
      iconTheme: IconThemeData(color: palette.ink),
      actionsIconTheme: IconThemeData(color: palette.ink),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: brandTransparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BrandGeometry.corners,
        side: BorderSide(
          color: palette.outline,
          width: BrandGeometry.borderWidth,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: brandTransparent,
      shape: RoundedRectangleBorder(borderRadius: BrandGeometry.corners),
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: brandTransparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BrandGeometry.radius),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: brandTransparent,
      shape: RoundedRectangleBorder(borderRadius: BrandGeometry.corners),
      textStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: palette.outlineVariant),
      labelStyle: textTheme.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BrandGeometry.corners),
    ),
    dividerTheme: DividerThemeData(
      color: palette.outlineVariant,
      thickness: 1,
      space: BrandGeometry.spacingMd,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: listTileTitleStyle(palette),
      subtitleTextStyle: listTileSubtitleStyle(palette),
      iconColor: palette.inkMuted,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: _inputBorder(palette.inkMuted),
      enabledBorder: _inputBorder(palette.inkMuted),
      focusedBorder: _inputBorder(palette.primary),
      errorBorder: _inputBorder(palette.error),
      focusedErrorBorder: _inputBorder(palette.error),
      labelStyle: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
      hintStyle: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        textStyle: textTheme.labelLarge,
        shape: _buttonShape,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: textTheme.labelLarge,
        shape: _buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.primary,
        side: BorderSide(
          color: palette.outline,
          width: BrandGeometry.borderWidth,
        ),
        textStyle: textTheme.labelLarge,
        shape: _buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: textTheme.labelLarge,
        shape: _buttonShape,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.secondary,
      foregroundColor: palette.onSecondary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.primary),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.primary,
      selectionColor: palette.primary.withValues(alpha: 0.25),
      selectionHandleColor: palette.primary,
    ),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BrandGeometry.corners,
  borderSide: BorderSide(color: color, width: BrandGeometry.borderWidth),
);

const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: BrandGeometry.corners,
);
