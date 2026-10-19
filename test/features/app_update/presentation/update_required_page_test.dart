import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/app_update/presentation/update_required_page.dart';

const storeUnavailableMessage =
    "Couldn't open the App Store. Please open it manually and update "
    'WishTogether.';
const stillBlockedMessage = 'Still not available. Try again later.';

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
      expect(find.text(stillBlockedMessage), findsOneWidget);
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
      expect(find.text(storeUnavailableMessage), findsOneWidget);
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

    testWidgets('disables both actions while the update is in flight', (
      tester,
    ) async {
      // Arrange
      final completer = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () {
              calls++;
              return completer.future;
            },
            onCheckAgain: () async => false,
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Update now'));
      await tester.pump();

      // Assert
      expect(calls, 1);
      expect(find.text('Opening…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);

      completer.complete(true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('disables both actions while the retry is in flight', (
      tester,
    ) async {
      // Arrange
      final completer = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () async => true,
            onCheckAgain: () {
              calls++;
              return completer.future;
            },
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Check again'));
      await tester.pump();

      // Assert
      expect(calls, 1);
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );

      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);

      completer.complete(false);
      await tester.pumpAndSettle();
      expect(find.text(stillBlockedMessage), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('recovers when an action throws', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () async => throw Exception('unavailable'),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(storeUnavailableMessage), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('re-checks when the app resumes', (tester) async {
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Assert
      expect(retries, 1);
    });

    testWidgets('recovers when the retry throws', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () async => true,
            onCheckAgain: () async => throw Exception('unavailable'),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(stillBlockedMessage), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('bounds a hung store action', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            updateTimeout: const Duration(milliseconds: 10),
            onUpdate: () => Completer<bool>().future,
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(storeUnavailableMessage), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('does not double-check on resume while a retry is in flight', (
      tester,
    ) async {
      // Arrange
      final completer = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredPage(
            message: 'Update',
            onUpdate: () async => true,
            onCheckAgain: () {
              calls++;
              return completer.future;
            },
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Check again'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Assert
      expect(calls, 1);

      completer.complete(false);
      await tester.pumpAndSettle();
    });
  });
}
