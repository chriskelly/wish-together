import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';

import '../../../core/logging/recording_sink.dart';

void main() {
  group('ClaimFailure.from', () {
    test('maps each classified code to its reason', () {
      // Arrange
      const expected = <String, ClaimFailureReason>{
        'permission-denied': ClaimFailureReason.accessDenied,
        'unavailable': ClaimFailureReason.offline,
        'not-found': ClaimFailureReason.itemMissing,
        'unauthenticated': ClaimFailureReason.signedOut,
      };

      // Act & Assert
      for (final entry in expected.entries) {
        final failure = ClaimFailure.from(CodedError(entry.key));

        expect(failure.reason, entry.value, reason: entry.key);
        expect(failure.code, entry.key);
      }
    });

    test('maps an unmapped code to unknown but keeps the code', () {
      // Arrange
      const String code = 'deadline-exceeded';

      // Act
      final failure = ClaimFailure.from(const CodedError(code));

      // Assert
      expect(failure.reason, ClaimFailureReason.unknown);
      expect(failure.code, code);
    });

    test('maps an error without a code to unknown', () {
      // Act
      final failure = ClaimFailure.from(StateError('boom'));

      // Assert
      expect(failure.reason, ClaimFailureReason.unknown);
      expect(failure.code, isNull);
    });

    test('keeps an existing ClaimFailure unchanged', () {
      // Arrange
      const failure = ClaimFailure(
        ClaimFailureReason.offline,
        code: 'unavailable',
      );

      // Act
      final classified = ClaimFailure.from(failure);

      // Assert
      expect(classified, same(failure));
    });
  });
}
