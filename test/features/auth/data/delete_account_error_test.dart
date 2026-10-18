import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/delete_account_error.dart';

void main() {
  FirebaseAuthException firebaseError(String code) =>
      FirebaseAuthException(code: code, message: 'raw-server-message');

  group('deleteAccountErrorMessage', () {
    test(
      'stays silent when the user backs out of a re-authentication prompt',
      () {
        // Act & Assert
        expect(
          deleteAccountErrorMessage(firebaseError(reauthCancelledCode)),
          isNull,
        );
      },
    );

    test('stays silent when the web sign-in popup is dismissed', () {
      // Act & Assert
      expect(
        deleteAccountErrorMessage(firebaseError('popup-closed-by-user')),
        isNull,
      );
      expect(
        deleteAccountErrorMessage(firebaseError('cancelled-popup-request')),
        isNull,
      );
    });

    test('stays silent when the Apple sheet is cancelled', () {
      // Arrange
      final canceled = SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'User canceled authorization',
      );

      // Act & Assert
      expect(deleteAccountErrorMessage(canceled), isNull);
    });

    group('Firebase codes', () {
      // Every code the mapper handles, paired with a substring its message must
      // contain so a branch cannot silently collapse into the generic message.
      const expectations = <String, String>{
        'requires-recent-login': 'confirm',
        'too-many-requests': 'wait',
        'network-request-failed': 'connection',
      };

      for (final entry in expectations.entries) {
        test('explains ${entry.key}', () {
          // Act
          final message = deleteAccountErrorMessage(firebaseError(entry.key));

          // Assert
          expect(message, isNotNull);
          expect(message!.toLowerCase(), contains(entry.value));
        });
      }
    });

    test(
      'falls back to a generic message for an unrecognised Firebase error',
      () {
        // Act
        final message = deleteAccountErrorMessage(
          firebaseError('some-unexpected-code'),
        );

        // Assert
        expect(message, isNotNull);
        expect(message!.trim(), isNotEmpty);
      },
    );

    test('falls back to a generic message for a non-Firebase error', () {
      // Act
      final message = deleteAccountErrorMessage(StateError('boom'));

      // Assert
      expect(message, isNotNull);
      expect(message!.trim(), isNotEmpty);
    });
  });
}
