import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/core/theme.dart';

const label = 'Claimed';

Widget host(StatusPillTone tone) => MaterialApp(
  theme: lightTheme,
  home: Scaffold(
    body: StatusPill(label: label, tone: tone),
  ),
);

ShapeDecoration shapeOf(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(StatusPill),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as ShapeDecoration;
}

TextStyle styleOf(WidgetTester tester) =>
    tester.widget<Text>(find.text(label)).style!;

void main() {
  testWidgets('neutral is outlined with muted ink', (tester) async {
    await tester.pumpWidget(host(StatusPillTone.neutral));

    final scheme = lightTheme.colorScheme;
    final shape = shapeOf(tester).shape as RoundedRectangleBorder;

    expect(shape.side.color, scheme.onSurfaceVariant);
    expect(shapeOf(tester).color, isNull);
    expect(styleOf(tester).color, scheme.onSurfaceVariant);
  });

  testWidgets('accent is filled with brass and uses onSecondary text', (
    tester,
  ) async {
    await tester.pumpWidget(host(StatusPillTone.accent));

    final scheme = lightTheme.colorScheme;
    final shape = shapeOf(tester).shape as RoundedRectangleBorder;

    expect(shapeOf(tester).color, scheme.secondary);
    expect(shape.side, BorderSide.none);
    expect(styleOf(tester).color, scheme.onSecondary);
  });
}
