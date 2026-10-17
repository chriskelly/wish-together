import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';

void main() {
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

    test('explains an account that already exists for the email', () {
      // Arrange
      final conflict = FirebaseAuthException(
        code: 'account-exists-with-different-credential',
        message: 'raw-server-message',
      );
      final fallback = appleAuthErrorMessage(
        FirebaseAuthException(code: 'some-future-code'),
      );

      // Act
      final message = appleAuthErrorMessage(conflict);

      // Assert
      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('account'));
      expect(message, isNot(fallback));
    });

    test('gives the "provider not enabled" code its own message', () {
      // Arrange
      final notEnabled = FirebaseAuthException(code: 'operation-not-allowed');
      final fallback = appleAuthErrorMessage(
        FirebaseAuthException(code: 'some-future-code'),
      );

      // Act
      final message = appleAuthErrorMessage(notEnabled);

      // Assert
      expect(message, isNotNull);
      expect(message, isNot(fallback));
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
  });
}
