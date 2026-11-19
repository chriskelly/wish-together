import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/features/auth/data/google_auth_error.dart';

void main() {
  group('isGoogleSignInCancellation', () {
    test('treats a native canceled code as a cancellation', () {
      // Arrange
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );

      // Act
      final result = isGoogleSignInCancellation(error);

      // Assert
      expect(result, isTrue);
    });

    test('treats the web access_denied response as a cancellation', () {
      // Arrange: google_sign_in_web wraps the GIS credential-response error
      // string in unknownError, and a denied popup reports access_denied.
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'access_denied',
      );

      // Act
      final result = isGoogleSignInCancellation(error);

      // Assert
      expect(result, isTrue);
    });

    test('treats the web popup_closed_by_user response as a cancellation', () {
      // Arrange
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'popup_closed_by_user',
      );

      // Act
      final result = isGoogleSignInCancellation(error);

      // Assert
      expect(result, isTrue);
    });

    test(
      'does not treat another unknownError description as a cancellation',
      () {
        // Arrange
        const error = GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'the network went away',
        );

        // Act
        final result = isGoogleSignInCancellation(error);

        // Assert
        expect(result, isFalse);
      },
    );

    test('does not treat another Google code as a cancellation', () {
      // Arrange
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );

      // Act
      final result = isGoogleSignInCancellation(error);

      // Assert
      expect(result, isFalse);
    });

    test('does not treat a non-Google error as a cancellation', () {
      // Arrange
      final error = StateError('not a Google failure');

      // Act
      final result = isGoogleSignInCancellation(error);

      // Assert
      expect(result, isFalse);
    });
  });

  group('googleSignInFailureCode', () {
    test('keeps a single-word enum name', () {
      // Arrange
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );

      // Act
      final code = googleSignInFailureCode(error);

      // Assert
      expect(code, 'canceled');
    });

    test('turns a camel-case enum name into a kebab-case code', () {
      // Arrange
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );

      // Act
      final code = googleSignInFailureCode(error);

      // Assert: redactCode drops a bare camel-case token this long as id-shaped,
      // so the separators are what keep the code on the wire.
      expect(code, 'client-configuration-error');
      expect(redactCode(code), code);
    });

    test('every enum value maps to a code the wire keeps', () {
      for (final value in GoogleSignInExceptionCode.values) {
        // Arrange
        final error = GoogleSignInException(code: value);

        // Act
        final code = googleSignInFailureCode(error);

        // Assert
        expect(redactCode(code), code, reason: 'code for $value must survive');
      }
    });
  });
}
