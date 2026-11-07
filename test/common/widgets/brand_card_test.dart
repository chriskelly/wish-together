import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/core/design_tokens.dart';
import 'package:wishtogether/core/theme.dart';

const childText = 'Beach trip';

Widget host(ThemeData theme, {Color? fill}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: BrandCard(backgroundColor: fill, child: const Text(childText)),
  ),
);

Card cardOf(WidgetTester tester) => tester.widget<Card>(
  find.descendant(of: find.byType(BrandCard), matching: find.byType(Card)),
);

BoxDecoration decorationOf(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(BrandCard),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('paints a hard offset shadow in light', (tester) async {
    await tester.pumpWidget(host(lightTheme));

    final shadows = decorationOf(tester).boxShadow!;

    expect(shadows, hasLength(1));
    expect(shadows.single.offset, const Offset(4, 4));
    expect(shadows.single.blurRadius, 0);
    expect(shadows.single.color, BrandPalette.light.shadow);
  });

  testWidgets('drops the offset shadow in dark', (tester) async {
    await tester.pumpWidget(host(darkTheme));

    final shadows = decorationOf(tester).boxShadow ?? const <BoxShadow>[];

    expect(shadows, isEmpty);
  });

  testWidgets('keeps a Material Card between the decoration and the child', (
    tester,
  ) async {
    await tester.pumpWidget(host(lightTheme));

    expect(
      find.descendant(of: find.byType(BrandCard), matching: find.byType(Card)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text(childText), matching: find.byType(Material)),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('defaults to the documented vertical margin', (tester) async {
    await tester.pumpWidget(host(lightTheme));

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(BrandCard),
        matching: find.byType(Container),
      ),
    );

    expect(
      container.margin,
      const EdgeInsets.symmetric(vertical: BrandGeometry.cardMarginVertical),
    );
  });

  testWidgets('uses the surface fill by default', (tester) async {
    await tester.pumpWidget(host(lightTheme));

    expect(cardOf(tester).color, lightTheme.colorScheme.surfaceContainerLow);
  });

  testWidgets('uses an explicit fill when given', (tester) async {
    await tester.pumpWidget(
      host(lightTheme, fill: lightTheme.colorScheme.surfaceContainerHighest),
    );

    expect(
      cardOf(tester).color,
      lightTheme.colorScheme.surfaceContainerHighest,
    );
  });
}
