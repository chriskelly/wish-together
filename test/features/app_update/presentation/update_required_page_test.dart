import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/app_update/presentation/update_required_page.dart';

void main() {
  group('UpdateRequiredPage', () {
    testWidgets('shows the configured message', (tester) async {
      // Arrange
      const message = 'Please update to keep using WishTogether.';

      // Act
      await tester.pumpWidget(
        const MaterialApp(home: UpdateRequiredPage(message: message)),
      );

      // Assert
      expect(find.text(message), findsOneWidget);
    });

    testWidgets('calls onUpdate when the update button is tapped', (
      tester,
    ) async {
      // Arrange
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(message: 'Update', onUpdate: () => taps++),
        ),
      );

      // Act
      await tester.tap(find.text('Update now'));

      // Assert
      expect(taps, 1);
    });

    testWidgets('disables the update button without an action', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(home: UpdateRequiredPage(message: 'Update')),
      );

      // Act
      final button = tester.widget<FilledButton>(find.byType(FilledButton));

      // Assert
      expect(button.onPressed, isNull);
    });

    testWidgets('offers a retry when onCheckAgain is provided', (tester) async {
      // Arrange
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onCheckAgain: () async {
              retries++;
            },
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Check again'));
      await tester.pump();

      // Assert
      expect(retries, 1);
    });

    testWidgets('hides the retry when onCheckAgain is absent', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(home: UpdateRequiredPage(message: 'Update')),
      );

      // Assert
      expect(find.text('Check again'), findsNothing);
    });
  });
}
