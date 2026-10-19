import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/app_update/application/retry_update_gate.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

void main() {
  group('retryUpdateGate', () {
    test('does not start the app when the retry is blocked', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.blocked(
          message: 'Update',
          updateUrl: 'https://apps.apple.com/app/id1234567890',
        ),
        start: () => started = true,
      );

      // Assert
      expect(result, isFalse);
      expect(started, isFalse);
    });

    test('does not start the app when the retry fails open', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.allowed(),
        start: () => started = true,
      );

      // Assert
      expect(result, isFalse);
      expect(started, isFalse);
    });

    test('starts the app when the retry is conclusive', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.allowed(isConclusive: true),
        start: () => started = true,
      );

      // Assert
      expect(result, isTrue);
      expect(started, isTrue);
    });
  });
}
