import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/data/reauth_provider.dart';

void main() {
  group('preferredReauthProvider', () {
    test('uses the provider that issued the session token', () {
      expect(
        preferredReauthProvider(
          signInProvider: 'google.com',
          providerIds: const ['phone', 'google.com'],
          isWeb: false,
        ),
        ReauthProvider.google,
      );
    });

    test('uses the Apple flow when Apple issued the session token', () {
      expect(
        preferredReauthProvider(
          signInProvider: 'apple.com',
          providerIds: const ['apple.com'],
          isWeb: false,
        ),
        ReauthProvider.apple,
      );
    });

    test('uses the phone flow when phone issued the session token', () {
      expect(
        preferredReauthProvider(
          signInProvider: 'phone',
          providerIds: const ['phone'],
          isWeb: false,
        ),
        ReauthProvider.phone,
      );
    });

    test(
      'falls back to the linked providers when the token provider is unknown',
      () {
        expect(
          preferredReauthProvider(
            signInProvider: 'password',
            providerIds: const ['google.com'],
            isWeb: false,
          ),
          ReauthProvider.google,
        );
      },
    );

    test('prefers phone over Google over Apple among the linked providers', () {
      expect(
        preferredReauthProvider(
          signInProvider: null,
          providerIds: const ['apple.com', 'google.com', 'phone'],
          isWeb: false,
        ),
        ReauthProvider.phone,
      );
    });

    test('skips Apple on the web, where it cannot be re-authenticated', () {
      expect(
        preferredReauthProvider(
          signInProvider: null,
          providerIds: const ['apple.com'],
          isWeb: true,
        ),
        ReauthProvider.unknown,
      );
    });

    test('falls through to Google on the web when Apple is linked', () {
      expect(
        preferredReauthProvider(
          signInProvider: null,
          providerIds: const ['apple.com', 'google.com'],
          isWeb: true,
        ),
        ReauthProvider.google,
      );
    });

    test('is unknown when the account has no usable provider', () {
      expect(
        preferredReauthProvider(
          signInProvider: null,
          providerIds: const ['anonymous'],
          isWeb: false,
        ),
        ReauthProvider.unknown,
      );
    });
  });
}
