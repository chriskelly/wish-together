import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';

void main() {
  FirebaseAuthException firebaseError(String code) =>
      FirebaseAuthException(code: code, message: 'raw-server-message');

  group('appleAuthErrorMessage', () {
    test('stays silent when the user cancels the Apple sheet', () {
      // Arrange
      final canceled = SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'User canceled authorization',
      );

      // Act
      final message = appleAuthErrorMessage(canceled);

      // Assert
      expect(message, isNull);
    });

    test('reports a failed authorization', () {
      // Arrange
      final failed = SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'The authorization attempt failed.',
      );

      // Act
      final message = appleAuthErrorMessage(failed);

      // Assert
      expect(message, isNotNull);
      expect(message!.trim(), isNotEmpty);
    });

    test('tells the user Apple sign-in is unavailable on this device', () {
      // Arrange
      const notSupported = SignInWithAppleNotSupportedException(
        message: 'Sign in with Apple is not available.',
      );

      // Act
      final message = appleAuthErrorMessage(notSupported);

      // Assert
      expect(message, isNotNull);
      expect(message!.trim(), isNotEmpty);
    });

    test('falls back to a generic message for an unrecognised error', () {
      // Arrange
      final unknown = StateError('boom');

      // Act
      final message = appleAuthErrorMessage(unknown);

      // Assert
      expect(message, isNotNull);
      expect(message!.trim(), isNotEmpty);
    });

    test(
      'falls back to a generic message for a non-authorization Apple error',
      () {
        // Arrange
        const credentialsError = SignInWithAppleCredentialsException(
          message: 'Keychain lookup failed.',
        );

        // Act
        final message = appleAuthErrorMessage(credentialsError);

        // Assert
        expect(message, isNotNull);
        expect(message!.trim(), isNotEmpty);
      },
    );

    group('Firebase codes', () {
      // Every code the mapper handles, paired with a substring its message must
      // contain so a branch cannot silently collapse into the generic message.
      const expectations = <String, String>{
        'account-exists-with-different-credential': 'account',
        'operation-not-allowed': 'not enabled',
        'credential-already-in-use': 'already linked',
        appleMissingIdTokenCode: 'token',
        'missing-or-invalid-nonce': 'verify',
        'network-request-failed': 'connection',
      };

      test('gives every handled code a message of its own', () {
        // Act
        final messages = <String>[];
        for (final code in expectations.keys) {
          final message = appleAuthErrorMessage(firebaseError(code));
          expect(message, isNotNull, reason: code);
          expect(message!.trim(), isNotEmpty, reason: code);
          messages.add(message);
        }

        // Assert
        expect(
          messages.toSet().length,
          expectations.length,
          reason: 'each handled code should read differently',
        );
      });

      for (final entry in expectations.entries) {
        test('explains ${entry.key}', () {
          // Act
          final message = appleAuthErrorMessage(firebaseError(entry.key));

          // Assert
          expect(message, isNotNull);
          expect(message!.toLowerCase(), contains(entry.value));
        });
      }
    });
  });
}
