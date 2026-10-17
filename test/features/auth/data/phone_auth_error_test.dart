import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/data/phone_auth_error.dart';

void main() {
  FirebaseAuthException exceptionFor(String code) =>
      FirebaseAuthException(code: code, message: 'raw-server-message');

  group('phoneAuthErrorMessage', () {
    // Codes the phone flow must handle explicitly (ticket #8).
    const knownCodes = <String>[
      'invalid-phone-number',
      'too-many-requests',
      'invalid-verification-code',
      'code-expired',
      'invalid-app-credential',
      'unauthorized-domain',
      'quota-exceeded',
    ];

    test('gives every known code its own non-empty message', () {
      // Arrange
      final genericFallback = phoneAuthErrorMessage(
        exceptionFor('brand-new-code'),
      );

      // Act
      final messages = knownCodes
          .map((code) => phoneAuthErrorMessage(exceptionFor(code)))
          .toList();

      // Assert
      expect(messages.every((message) => message.trim().isNotEmpty), isTrue);
      expect(
        messages,
        isNot(contains(genericFallback)),
        reason: 'a known code must not fall through to the generic message',
      );
    });

    test(
      'tells the user the host is not authorized for unauthorized-domain',
      () {
        // Act
        final message = phoneAuthErrorMessage(
          exceptionFor('unauthorized-domain'),
        );

        // Assert
        expect(message.toLowerCase(), contains('domain'));
      },
    );

    test('falls back to a generic message for an unrecognised code', () {
      // Act
      final message = phoneAuthErrorMessage(exceptionFor('some-future-code'));

      // Assert
      expect(message.trim(), isNotEmpty);
    });

    test('falls back to a generic message when no code is supplied', () {
      // Act
      final message = phoneAuthErrorMessage(exceptionFor(''));

      // Assert
      expect(message.trim(), isNotEmpty);
    });
  });
}
