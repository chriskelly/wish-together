import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/app_update/application/check_for_update.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

void main() {
  group('checkForUpdate', () {
    test('returns the check result unchanged', () async {
      // Arrange
      const decision = UpdateDecision.allowed(isConclusive: true);

      // Act
      final result = await checkForUpdate(() async => decision);

      // Assert
      expect(result.isBlocked, isFalse);
      expect(result.isConclusive, isTrue);
    });

    test('turns a throw into an inconclusive allowance', () async {
      // Act
      final result = await checkForUpdate(
        () async => throw Exception('unavailable'),
      );

      // Assert
      expect(result.isBlocked, isFalse);
      expect(result.isConclusive, isFalse);
    });
  });
}
