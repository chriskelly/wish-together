import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

void main() {
  group('evaluateUpdate', () {
    const customMessage = 'A newer WishTogether is required.';
    const customUrl = 'https://apps.apple.com/app/id123';

    UpdateDecision evaluate({
      required int? runningBuild,
      required int minSupportedBuild,
      bool conclusive = true,
      String message = customMessage,
      String updateUrl = customUrl,
    }) {
      return evaluateUpdate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
        message: message,
        updateUrl: updateUrl,
        conclusive: conclusive,
      );
    }

    test('does not block when the kill switch is at zero', () {
      // Arrange
      const runningBuild = 5;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: 0,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('does not block when the running build equals the minimum', () {
      // Arrange
      const runningBuild = 12;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: runningBuild,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('does not block when the running build is above the minimum', () {
      // Arrange
      const minSupportedBuild = 12;
      const runningBuild = minSupportedBuild + 1;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('blocks when the running build is below the minimum', () {
      // Arrange
      const minSupportedBuild = 12;
      const runningBuild = minSupportedBuild - 1;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
      );

      // Assert
      expect(decision.isBlocked, isTrue);
      expect(decision.isConclusive, isTrue);
      expect(decision.message, customMessage);
      expect(decision.updateUrl, customUrl);
    });

    test('does not block when the running build is unknown', () {
      // Arrange
      const minSupportedBuild = 12;

      // Act
      final decision = evaluate(
        runningBuild: null,
        minSupportedBuild: minSupportedBuild,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('does not block when the check is inconclusive', () {
      // Arrange
      const minSupportedBuild = 12;
      const runningBuild = minSupportedBuild - 1;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
        conclusive: false,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('does not block when the update URL is not usable', () {
      // Arrange
      const minSupportedBuild = 12;
      const runningBuild = minSupportedBuild - 1;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
        updateUrl: '',
      );

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      expect(decision.blockedForMissingUpdateUrl, isTrue);
    });

    test('falls back to the default message when none is configured', () {
      // Arrange
      const minSupportedBuild = 12;
      const runningBuild = minSupportedBuild - 1;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
        message: '',
      );

      // Assert
      expect(decision.isBlocked, isTrue);
      expect(decision.message, defaultUpdateMessage);
    });

    test('treats a negative minimum as inert', () {
      // Arrange
      const minSupportedBuild = -1;
      const runningBuild = 1;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: minSupportedBuild,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('marks an allowance from a completed check as conclusive', () {
      // Arrange
      const runningBuild = 5;

      // Act
      final decision = evaluate(
        runningBuild: runningBuild,
        minSupportedBuild: 0,
        conclusive: true,
      );

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isTrue);
    });
  });

  group('canStartFromRetry', () {
    test('refuses to unlock a confirmed block', () {
      // Arrange
      const decision = UpdateDecision.blocked(
        message: 'Update',
        updateUrl: 'https://apps.apple.com/app/id123',
      );

      // Act & Assert
      expect(canStartFromRetry(decision), isFalse);
    });

    test('refuses to unlock an inconclusive allowance', () {
      // Arrange
      const decision = UpdateDecision.allowed(isConclusive: false);

      // Act & Assert
      expect(canStartFromRetry(decision), isFalse);
    });

    test('unlocks a conclusive allowance', () {
      // Arrange
      const decision = UpdateDecision.allowed(isConclusive: true);

      // Act & Assert
      expect(canStartFromRetry(decision), isTrue);
    });
  });
}
