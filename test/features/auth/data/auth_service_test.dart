import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockConfirmationResult extends Mock implements ConfirmationResult {}

class MockUserCredential extends Mock implements UserCredential {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      PhoneAuthProvider.credential(
        verificationId: 'fallback-verification-id',
        smsCode: '000000',
      ),
    );
    registerFallbackValue(
      OAuthProvider('apple.com').credential(idToken: 'fallback-identity-token'),
    );
  });

  late MockFirebaseAuth mockAuth;

  setUp(() {
    mockAuth = MockFirebaseAuth();
  });

  group('AuthService.startWebPhoneSignIn', () {
    test('requests an SMS via signInWithPhoneNumber and returns the verification id', () async {
      // Arrange
      const phoneNumber = '+15550001111';
      const verificationId = 'web-verification-id';
      final confirmationResult = MockConfirmationResult();
      when(() => mockAuth.signInWithPhoneNumber(phoneNumber))
          .thenAnswer((_) async => confirmationResult);
      when(() => confirmationResult.verificationId).thenReturn(verificationId);

      final authService = AuthService(auth: mockAuth, isWeb: true);

      // Act
      final result = await authService.startWebPhoneSignIn(phoneNumber);

      // Assert
      expect(result, verificationId);
      verify(() => mockAuth.signInWithPhoneNumber(phoneNumber)).called(1);
    });
  });

  group('AuthService.confirmPhoneCode', () {
    test(
      'on web, finishes with the stashed confirmation rather than a credential',
      () async {
        // Arrange
        const phoneNumber = '+15550001111';
        const smsCode = '654321';
        final confirmationResult = MockConfirmationResult();
        final userCredential = MockUserCredential();
        when(() => mockAuth.signInWithPhoneNumber(phoneNumber))
            .thenAnswer((_) async => confirmationResult);
        when(() => confirmationResult.verificationId)
            .thenReturn('web-verification-id');
        when(() => confirmationResult.confirm(smsCode))
            .thenAnswer((_) async => userCredential);

        final authService = AuthService(auth: mockAuth, isWeb: true);
        final verificationId = await authService.startWebPhoneSignIn(
          phoneNumber,
        );

        // Act
        final result = await authService.confirmPhoneCode(
          verificationId: verificationId,
          smsCode: smsCode,
        );

        // Assert
        expect(result, same(userCredential));
        verify(() => confirmationResult.confirm(smsCode)).called(1);
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );

    test('on native, signs in with a credential built from the verification id and code', () async {
      // Arrange
      const verificationId = 'native-verification-id';
      const smsCode = '654321';
      final userCredential = MockUserCredential();
      when(() => mockAuth.signInWithCredential(any()))
          .thenAnswer((_) async => userCredential);

      final authService = AuthService(auth: mockAuth, isWeb: false);

      // Act
      final result = await authService.confirmPhoneCode(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      // Assert
      expect(result, same(userCredential));
      final credential =
          verify(() => mockAuth.signInWithCredential(captureAny()))
                  .captured
                  .single
              as PhoneAuthCredential;
      expect(credential.verificationId, verificationId);
      expect(credential.smsCode, smsCode);
    });
  });

  group('AuthService.signInWithApple', () {
    const identityToken = 'apple-identity-token';
    const authorizationCode = 'apple-authorization-code';

    AuthorizationCredentialAppleID appleCredential(String? token) =>
        AuthorizationCredentialAppleID(
          userIdentifier: 'apple-user-id',
          givenName: null,
          familyName: null,
          authorizationCode: authorizationCode,
          email: null,
          identityToken: token,
          state: null,
        );

    test('exchanges the Apple credential for a Firebase session', () async {
      // Arrange
      final userCredential = MockUserCredential();
      when(() => mockAuth.signInWithCredential(any()))
          .thenAnswer((_) async => userCredential);
      final appleService = AuthService(
        auth: mockAuth,
        appleCredentialFetcher: ({
          required List<AppleIDAuthorizationScopes> scopes,
          String? nonce,
        }) async => appleCredential(identityToken),
      );

      // Act
      final result = await appleService.signInWithApple();

      // Assert
      expect(result, same(userCredential));
      final credential =
          verify(() => mockAuth.signInWithCredential(captureAny()))
                  .captured
                  .single
              as OAuthCredential;
      expect(credential.providerId, 'apple.com');
      expect(credential.idToken, identityToken);
      // Apple's authorization code is passed as the access token for the
      // native iOS exchange — pin it so a "cleanup" cannot silently drop it.
      expect(credential.accessToken, authorizationCode);
    });

    test(
      'sends Apple the SHA-256 of the raw nonce it gives Firebase',
      () async {
        // Arrange
        when(() => mockAuth.signInWithCredential(any()))
            .thenAnswer((_) async => MockUserCredential());
        String? nonceSentToApple;
        final appleService = AuthService(
          auth: mockAuth,
          appleCredentialFetcher:
              ({
                required List<AppleIDAuthorizationScopes> scopes,
                String? nonce,
              }) async {
                nonceSentToApple = nonce;
                return appleCredential(identityToken);
              },
        );

        // Act
        await appleService.signInWithApple();

        // Assert
        final credential =
            verify(() => mockAuth.signInWithCredential(captureAny()))
                    .captured
                    .single
                as OAuthCredential;
        final rawNonce = credential.rawNonce;
        expect(rawNonce, isNotNull);
        expect(
          sha256.convert(utf8.encode(rawNonce!)).toString(),
          nonceSentToApple,
        );
      },
    );

    test('requests only the email scope', () async {
      // Arrange
      when(() => mockAuth.signInWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());
      List<AppleIDAuthorizationScopes>? requestedScopes;
      final appleService = AuthService(
        auth: mockAuth,
        appleCredentialFetcher:
            ({
              required List<AppleIDAuthorizationScopes> scopes,
              String? nonce,
            }) async {
              requestedScopes = scopes;
              return appleCredential(identityToken);
            },
      );

      // Act
      await appleService.signInWithApple();

      // Assert
      expect(requestedScopes, [AppleIDAuthorizationScopes.email]);
    });

    test('throws when Apple returns no identity token', () async {
      // Arrange
      final appleService = AuthService(
        auth: mockAuth,
        appleCredentialFetcher: ({
          required List<AppleIDAuthorizationScopes> scopes,
          String? nonce,
        }) async => appleCredential(null),
      );

      // Act & Assert
      await expectLater(
        appleService.signInWithApple(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            appleMissingIdTokenCode,
          ),
        ),
      );
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });

    test('propagates an error from the Apple sheet', () async {
      // Arrange
      final error = SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'nope',
      );
      final appleService = AuthService(
        auth: mockAuth,
        appleCredentialFetcher: ({
          required List<AppleIDAuthorizationScopes> scopes,
          String? nonce,
        }) async => throw error,
      );

      // Act & Assert
      await expectLater(appleService.signInWithApple(), throwsA(same(error)));
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });
  });
}
