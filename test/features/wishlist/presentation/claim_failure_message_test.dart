import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/presentation/claim_failure_message.dart';

void main() {
  group('claimFailureMessage', () {
    test('explains a denied claim without naming the error code', () {
      // Arrange
      final error = ClaimFailure(
        ClaimFailureReason.accessDenied,
        code: 'permission-denied',
      );

      // Act
      final message = claimFailureMessage(error);

      // Assert
      expect(
        message,
        "This item can't be claimed right now. It may already be claimed, or "
        'the wishlist may no longer be shared with you.',
      );
      expect(message, isNot(contains('permission-denied')));
    });

    test(
      'tells the reader to check the connection when the server is unreachable',
      () {
        // Arrange
        const error = ClaimFailure(ClaimFailureReason.offline);

        // Act
        final message = claimFailureMessage(error);

        // Assert
        expect(
          message,
          "Couldn't reach the server. Check your connection and try again.",
        );
      },
    );

    test('reports a deleted item as gone', () {
      // Arrange
      const error = ClaimFailure(ClaimFailureReason.itemMissing);

      // Act
      final message = claimFailureMessage(error);

      // Assert
      expect(message, 'This item no longer exists.');
    });

    test('asks a signed-out reader to sign in again', () {
      // Arrange
      const error = ClaimFailure(ClaimFailureReason.signedOut);

      // Act
      final message = claimFailureMessage(error);

      // Assert
      expect(message, 'Please sign in again to claim items.');
    });

    test('falls back to a generic message for an unclassified failure', () {
      // Arrange
      final error = Exception('boom');

      // Act
      final message = claimFailureMessage(error);

      // Assert
      expect(message, "Couldn't claim this item. Please try again.");
      expect(message, isNot(contains('boom')));
    });
  });
}
