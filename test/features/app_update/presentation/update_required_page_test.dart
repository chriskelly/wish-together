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
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () async {
              taps++;
              return true;
            },
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

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
              return false;
            },
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();

      // Assert
      expect(retries, 1);
      expect(
        find.text('Still not available. Try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('hides the retry when onCheckAgain is absent', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(home: UpdateRequiredPage(message: 'Update')),
      );

      // Assert
      expect(find.text('Check again'), findsNothing);
    });

    testWidgets('shows a message when the store cannot open', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () async => false,
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(
          "Couldn't open the App Store. Please open it manually and update "
          'WishTogether.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps the update action reachable with a long message', (
      tester,
    ) async {
      // Arrange
      const surface = Size(320, 480);
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final longMessage = List.filled(
        40,
        'A very long update message.',
      ).join(' ');
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: longMessage,
            onUpdate: () async => true,
          ),
        ),
      );

      // Act
      await tester.ensureVisible(find.text('Update now'));
      await tester.pumpAndSettle();

      // Assert
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      final buttonRect = tester.getRect(find.text('Update now'));
      expect(buttonRect.top, greaterThanOrEqualTo(0));
      expect(buttonRect.bottom, lessThanOrEqualTo(surface.height));
    });
  });
}
