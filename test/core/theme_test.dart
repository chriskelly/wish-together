import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/design_tokens.dart';
import 'package:wishtogether/core/theme.dart';

void main() {
  final themes = <(BrandPalette, ThemeData)>[
    (BrandPalette.light, lightTheme),
    (BrandPalette.dark, darkTheme),
  ];

  for (final (palette, theme) in themes) {
    test('${palette.brightness.name} theme resolves every surface', () {
      expect(theme.brightness, palette.brightness);
      expect(theme.scaffoldBackgroundColor, palette.canvas);
      expect(theme.colorScheme, palette.toColorScheme());
    });

    test('${palette.brightness.name} theme styles every component', () {
      final scheme = theme.colorScheme;

      expect(theme.appBarTheme.backgroundColor, palette.canvas);
      expect(theme.appBarTheme.foregroundColor, palette.ink);
      // ThemeData merges typography into textTheme after construction, so the
      // assigned style and the resolved one differ by debug labels and
      // decoration; the role's fields are what matter.
      final appBarTitle = theme.appBarTheme.titleTextStyle!;
      expect(appBarTitle.fontFamily, archivoBlackFamily);
      expect(appBarTitle.fontSize, 21);
      expect(appBarTitle.color, palette.ink);

      final card = theme.cardTheme;
      final cardShape = card.shape! as RoundedRectangleBorder;
      expect(card.color, scheme.surfaceContainerLow);
      expect(card.elevation, 0);
      expect(cardShape.borderRadius, BrandGeometry.corners);
      expect(cardShape.side.color, palette.outline);
      expect(cardShape.side.width, BrandGeometry.borderWidth);

      expect(theme.dialogTheme.backgroundColor, scheme.surfaceContainerHigh);
      expect(
        theme.bottomSheetTheme.backgroundColor,
        scheme.surfaceContainerLow,
      );
      expect(theme.snackBarTheme.backgroundColor, scheme.inverseSurface);
      expect(
        theme.snackBarTheme.contentTextStyle!.color,
        scheme.onInverseSurface,
      );

      expect(theme.chipTheme.side!.color, palette.outlineVariant);
      expect(theme.dividerTheme.color, palette.outlineVariant);

      expect(theme.listTileTheme.titleTextStyle, listTileTitleStyle(palette));
      expect(
        theme.listTileTheme.subtitleTextStyle,
        listTileSubtitleStyle(palette),
      );

      final input = theme.inputDecorationTheme;
      // A control boundary must reach 3:1 (WCAG 1.4.11); outlineVariant is
      // about 1.5:1, so enabled borders use the muted ink.
      expect(
        (input.enabledBorder! as OutlineInputBorder).borderSide.color,
        palette.inkMuted,
      );
      expect(
        (input.focusedBorder! as OutlineInputBorder).borderSide.color,
        palette.primary,
      );

      expect(
        theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
        palette.primary,
      );
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        palette.secondary,
      );
      expect(
        theme.floatingActionButtonTheme.foregroundColor,
        palette.onSecondary,
      );
      expect(theme.progressIndicatorTheme.color, palette.primary);
      expect(theme.iconTheme.color, palette.ink);
    });
  }
}
