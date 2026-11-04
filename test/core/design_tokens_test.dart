import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/design_tokens.dart';

import '../support/contrast_ratio.dart';

void main() {
  for (final palette in <BrandPalette>[BrandPalette.light, BrandPalette.dark]) {
    group('${palette.brightness.name} palette', () {
      test('every text pair reaches 4.5:1', () {
        final pairs = <(String, Color, Color)>[
          ('ink on canvas', palette.ink, palette.canvas),
          ('ink on surface', palette.ink, palette.surface),
          ('inkMuted on canvas', palette.inkMuted, palette.canvas),
          ('inkMuted on surface', palette.inkMuted, palette.surface),
          (
            'inkMuted on surfaceContainerHighest',
            palette.inkMuted,
            palette.surfaceContainerHighest,
          ),
          ('primary on canvas', palette.primary, palette.canvas),
          ('primary on surface', palette.primary, palette.surface),
          ('onPrimary on primary', palette.onPrimary, palette.primary),
          ('onSecondary on secondary', palette.onSecondary, palette.secondary),
          ('error on canvas', palette.error, palette.canvas),
          ('error on surface', palette.error, palette.surface),
          ('onError on error', palette.onError, palette.error),
          (
            'onInverseSurface on inverseSurface',
            palette.onInverseSurface,
            palette.inverseSurface,
          ),
          (
            'ink on surfaceContainerHighest',
            palette.ink,
            palette.surfaceContainerHighest,
          ),
        ];

        for (final (name, foreground, background) in pairs) {
          final ratio = contrastRatio(foreground, background);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$name is ${ratio.toStringAsFixed(2)}:1 in '
                '${palette.brightness.name}',
          );
        }
      });

      test('every control boundary reaches 3:1', () {
        final boundaries = <(String, Color, Color)>[
          ('input border on surface', palette.inkMuted, palette.surface),
          ('card outline on surface', palette.outline, palette.surface),
          ('card outline on canvas', palette.outline, palette.canvas),
        ];

        for (final (name, foreground, background) in boundaries) {
          final ratio = contrastRatio(foreground, background);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '$name is ${ratio.toStringAsFixed(2)}:1 in '
                '${palette.brightness.name} (WCAG 1.4.11)',
          );
        }
      });

      test('${palette.brightness.name} scheme pins the documented slots', () {
        final scheme = palette.toColorScheme();

        expect(scheme.brightness, palette.brightness);
        expect(scheme.primary, palette.primary);
        expect(scheme.onPrimary, palette.onPrimary);
        expect(scheme.secondary, palette.secondary);
        expect(scheme.onSecondary, palette.onSecondary);
        expect(scheme.error, palette.error);
        expect(scheme.onError, palette.onError);
        expect(scheme.surface, palette.surface);
        expect(scheme.onSurface, palette.ink);
        expect(scheme.onSurfaceVariant, palette.inkMuted);
        expect(scheme.outline, palette.outline);
        expect(scheme.outlineVariant, palette.outlineVariant);
        expect(scheme.shadow, palette.shadow);
        expect(scheme.scrim, palette.scrim);
        expect(scheme.inverseSurface, palette.inverseSurface);
        expect(scheme.onInverseSurface, palette.onInverseSurface);
        expect(scheme.inversePrimary, palette.inversePrimary);

        expect(scheme.surfaceContainerLowest, palette.canvas);
        expect(scheme.surfaceContainerLow, palette.surface);
        expect(scheme.surfaceContainer, palette.surface);
        expect(scheme.surfaceContainerHigh, palette.surface);
        expect(scheme.surfaceContainerHighest, palette.surfaceContainerHighest);
      });

      test(
        '${palette.brightness.name} type scale matches the design foundation',
        () {
          final textTheme = buildTextTheme(palette);

          _expectStyle(
            textTheme.displayLarge,
            family: archivoBlackFamily,
            size: 46,
            height: 1.02,
            weight: FontWeight.w400,
            letterSpacing: -1.0,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.displayMedium,
            family: archivoBlackFamily,
            size: 34,
            height: 1.05,
            weight: FontWeight.w400,
            letterSpacing: -0.8,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.headlineMedium,
            family: archivoBlackFamily,
            size: 27,
            height: 1.10,
            weight: FontWeight.w400,
            letterSpacing: -0.5,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.headlineSmall,
            family: archivoBlackFamily,
            size: 21,
            height: 1.15,
            weight: FontWeight.w400,
            letterSpacing: -0.3,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.titleLarge,
            family: archivoBlackFamily,
            size: 19,
            height: 1.20,
            weight: FontWeight.w400,
            letterSpacing: -0.2,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.titleMedium,
            family: archivoFamily,
            size: 16,
            height: 1.30,
            weight: FontWeight.w700,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.bodyLarge,
            family: archivoFamily,
            size: 16,
            height: 1.50,
            weight: FontWeight.w400,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.bodyMedium,
            family: archivoFamily,
            size: 14.5,
            height: 1.50,
            weight: FontWeight.w400,
            color: palette.ink,
          );
          _expectStyle(
            textTheme.bodySmall,
            family: archivoFamily,
            size: 12.5,
            height: 1.40,
            weight: FontWeight.w400,
            color: palette.inkMuted,
          );
          _expectStyle(
            textTheme.labelLarge,
            family: archivoFamily,
            size: 13,
            height: 1.40,
            weight: FontWeight.w800,
            letterSpacing: 1.1,
            color: palette.ink,
          );
        },
      );
    });
  }

  test('hero roles are Pacifico 400', () {
    _expectStyle(
      heroHomeTextStyle,
      family: pacificoFamily,
      size: 38,
      height: 1.15,
      weight: FontWeight.w400,
    );
    _expectStyle(
      heroLoginTextStyle,
      family: pacificoFamily,
      size: 50,
      height: 1.25,
      weight: FontWeight.w400,
    );
  });

  test('brass is a fill on light and readable on dark', () {
    expect(
      contrastRatio(BrandPalette.light.secondary, BrandPalette.light.surface),
      lessThan(4.5),
      reason: 'a brass label would be unreadable on the light surface',
    );
    expect(
      contrastRatio(BrandPalette.dark.secondary, BrandPalette.dark.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('geometry matches the design foundation', () {
    expect(BrandGeometry.radius, 6);
    expect(BrandGeometry.borderWidth, 2);
    expect(BrandGeometry.spacingXs, 4);
    expect(BrandGeometry.spacingSm, 8);
    expect(BrandGeometry.spacingMd, 16);
    expect(BrandGeometry.spacingLg, 24);
    expect(BrandGeometry.spacingXl, 32);
    expect(BrandGeometry.sectionGap, 30);
    expect(BrandGeometry.cardMarginVertical, 7);
    expect(BrandGeometry.corners, BorderRadius.circular(6));
  });

  test('the card shadow is a light-mode device', () {
    expect(BrandPalette.light.shadowOffset, const Offset(4, 4));
    expect(BrandPalette.dark.shadowOffset, Offset.zero);
    for (final palette in <BrandPalette>[
      BrandPalette.light,
      BrandPalette.dark,
    ]) {
      expect(
        palette.shadow.computeLuminance(),
        lessThan(palette.canvas.computeLuminance()),
        reason: 'a shadow must be darker than its ground',
      );
    }
  });
}

void _expectStyle(
  TextStyle? style, {
  required String family,
  required double size,
  required double height,
  required FontWeight weight,
  double? letterSpacing,
  Color? color,
}) {
  expect(style, isNotNull);
  expect(style!.fontFamily, family);
  expect(style.fontSize, size);
  expect(style.height, height);
  expect(style.fontWeight, weight);
  if (letterSpacing != null) {
    expect(style.letterSpacing, closeTo(letterSpacing, 1e-9));
  }
  if (color != null) {
    expect(style.color, color);
  }
}
