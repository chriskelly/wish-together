import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/phone_verification.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockConfirmationResult extends Mock implements ConfirmationResult {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockUserInfo extends Mock implements UserInfo {}

class MockIdTokenResult extends Mock implements IdTokenResult {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      PhoneAuthProvider.credential(
        verificationId: 'fallback-verification-id',
        smsCode: '000000',
      ),
    );
    registerFallbackValue(
      GoogleAuthProvider.credential(
        idToken: 'fallback-id-token',
        accessToken: 'fallback-access-token',
      ),
    );
    registerFallbackValue(GoogleAuthProvider());
    registerFallbackValue((PhoneAuthCredential credential) {});
    registerFallbackValue((FirebaseAuthException error) {});
    registerFallbackValue((String verificationId, int? resendToken) {});
    registerFallbackValue((String verificationId) {});
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

  group('AuthService.deleteAccount', () {
    test('deletes the auth user and then revokes the Google grant', () async {
      // ARRANGE
      final user = MockUser();
      final googleSignIn = MockGoogleSignIn();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => googleSignIn.onCurrentUserChanged)
          .thenAnswer((_) => const Stream<GoogleSignInAccount?>.empty());
      when(() => user.delete()).thenAnswer((_) async {});
      when(() => googleSignIn.disconnect()).thenAnswer((_) async => null);

      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // ACT
      await service.deleteAccount();

      // ASSERT: disconnect revokes the provider grant; signOut only drops the
      // local session and would leave the app listed on the Google account.
      verifyInOrder([() => user.delete(), () => googleSignIn.disconnect()]);
      verifyNever(() => googleSignIn.signOut());
    });

    test('completes without error when no user is signed in', () async {
      // ARRANGE
      when(() => mockAuth.currentUser).thenReturn(null);
      final service = AuthService(auth: mockAuth);

      // ACT & ASSERT
      await expectLater(service.deleteAccount(), completes);
    });

    test('still succeeds when revoking the Google grant fails', () async {
      // ARRANGE: the account is deleted, but revoking fails.
      final user = MockUser();
      final googleSignIn = MockGoogleSignIn();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => googleSignIn.onCurrentUserChanged)
          .thenAnswer((_) => const Stream<GoogleSignInAccount?>.empty());
      when(() => user.delete()).thenAnswer((_) async {});
      when(() => googleSignIn.disconnect())
          .thenThrow(Exception('google unavailable'));

      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // ACT & ASSERT: the deletion already happened, so it must not be
      // reported as a failure.
      await expectLater(service.deleteAccount(), completes);
    });
  });

  group('AuthService.reauthenticateWithGoogle', () {
    test('on native, reauthenticates with a fresh Google credential', () async {
      // ARRANGE
      final user = MockUser();
      final googleSignIn = MockGoogleSignIn();
      final account = MockGoogleSignInAccount();
      final authentication = MockGoogleSignInAuthentication();
      const idToken = 'google-id-token';
      const accessToken = 'google-access-token';
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => googleSignIn.onCurrentUserChanged)
          .thenAnswer((_) => const Stream<GoogleSignInAccount?>.empty());
      when(() => googleSignIn.signIn()).thenAnswer((_) async => account);
      when(() => account.authentication)
          .thenAnswer((_) async => authentication);
      when(() => authentication.idToken).thenReturn(idToken);
      when(() => authentication.accessToken).thenReturn(accessToken);
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());

      final service = AuthService(
        auth: mockAuth,
        isWeb: false,
        googleSignIn: googleSignIn,
      );

      // ACT
      await service.reauthenticateWithGoogle();

      // ASSERT
      final credential =
          verify(() => user.reauthenticateWithCredential(captureAny()))
                  .captured
                  .single
              as OAuthCredential;
      expect(credential.providerId, 'google.com');
      expect(credential.idToken, idToken);
      expect(credential.accessToken, accessToken);
    });

    test('on web, reauthenticates with the Google popup', () async {
      // ARRANGE
      final user = MockUser();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithPopup(any()))
          .thenAnswer((_) async => MockUserCredential());

      final service = AuthService(auth: mockAuth, isWeb: true);

      // ACT
      await service.reauthenticateWithGoogle();

      // ASSERT
      final provider =
          verify(() => user.reauthenticateWithPopup(captureAny()))
                  .captured
                  .single
              as AuthProvider;
      expect(provider.providerId, 'google.com');
    });

    test(
      'throws a cancel code when the user dismisses the Google account picker',
      () async {
        // ARRANGE
        final user = MockUser();
        final googleSignIn = MockGoogleSignIn();
        when(() => mockAuth.currentUser).thenReturn(user);
        when(() => googleSignIn.onCurrentUserChanged)
            .thenAnswer((_) => const Stream<GoogleSignInAccount?>.empty());
        when(() => googleSignIn.signIn()).thenAnswer((_) async => null);

        final service = AuthService(
          auth: mockAuth,
          isWeb: false,
          googleSignIn: googleSignIn,
        );

        // ACT & ASSERT
        await expectLater(
          service.reauthenticateWithGoogle(),
          throwsA(
            isA<FirebaseAuthException>().having(
              (e) => e.code,
              'code',
              reauthCancelledCode,
            ),
          ),
        );
        verifyNever(() => user.reauthenticateWithCredential(any()));
      },
    );
  });

  group('AuthService.reauthenticateWithApple', () {
    test('reauthenticates with a fresh Apple credential', () async {
      // ARRANGE
      final user = MockUser();
      const identityToken = 'apple-identity-token';
      const authorizationCode = 'apple-authorization-code';
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());

      final service = AuthService(
        auth: mockAuth,
        appleCredentialFetcher:
            ({
              required List<AppleIDAuthorizationScopes> scopes,
              String? nonce,
            }) async => AuthorizationCredentialAppleID(
              userIdentifier: 'apple-user-id',
              givenName: null,
              familyName: null,
              authorizationCode: authorizationCode,
              email: null,
              identityToken: identityToken,
              state: null,
            ),
      );

      // ACT
      await service.reauthenticateWithApple();

      // ASSERT
      final credential =
          verify(() => user.reauthenticateWithCredential(captureAny()))
                  .captured
                  .single
              as OAuthCredential;
      expect(credential.providerId, 'apple.com');
      expect(credential.idToken, identityToken);
      // Apple's authorization code travels as the access token for the native
      // iOS exchange — pin it so a cleanup cannot silently drop it.
      expect(credential.accessToken, authorizationCode);
      expect(credential.rawNonce, isNotNull);
    });
  });

  group('AuthService.reauthenticateWithPhoneCode', () {
    test('reauthenticates with the credential built from the verification id and code', () async {
      // ARRANGE
      final user = MockUser();
      const verificationId = 'phone-verification-id';
      const smsCode = '654321';
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());

      final service = AuthService(auth: mockAuth);

      // ACT
      await service.reauthenticateWithPhoneCode(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      // ASSERT
      final credential =
          verify(() => user.reauthenticateWithCredential(captureAny()))
                  .captured
                  .single
              as PhoneAuthCredential;
      expect(credential.verificationId, verificationId);
      expect(credential.smsCode, smsCode);
    });
  });

  group('AuthService.signInProvider', () {
    test('returns the provider that issued the current ID token', () async {
      // ARRANGE
      final user = MockUser();
      final idTokenResult = MockIdTokenResult();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.getIdTokenResult())
          .thenAnswer((_) async => idTokenResult);
      when(() => idTokenResult.signInProvider).thenReturn('apple.com');

      final service = AuthService(auth: mockAuth);

      // ACT & ASSERT
      expect(await service.signInProvider(), 'apple.com');
    });

    test('returns null when no user is signed in', () async {
      // ARRANGE
      when(() => mockAuth.currentUser).thenReturn(null);
      final service = AuthService(auth: mockAuth);

      // ACT & ASSERT
      expect(await service.signInProvider(), isNull);
    });
  });

  group('AuthService.providerIds', () {
    test('lists the account linked provider ids', () async {
      // ARRANGE
      final user = MockUser();
      final google = MockUserInfo();
      final apple = MockUserInfo();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.providerData).thenReturn([google, apple]);
      when(() => google.providerId).thenReturn('google.com');
      when(() => apple.providerId).thenReturn('apple.com');

      final service = AuthService(auth: mockAuth);

      // ACT & ASSERT
      expect(service.providerIds, ['google.com', 'apple.com']);
    });
  });

  group('AuthService.startPhoneVerification', () {
    const phoneNumber = '+15550001111';

    /// Stubs `verifyPhoneNumber` and drives it the way [platform] describes.
    void simulatePlatform({
      PhoneAuthCredential? autoVerified,
      String? codeSentId,
      String? verificationIdOnTimeout,
      FirebaseAuthException? failure,
      String? thenCodeSentId,
    }) {
      when(
        () => mockAuth.verifyPhoneNumber(
          phoneNumber: any(named: 'phoneNumber'),
          verificationCompleted: any(named: 'verificationCompleted'),
          verificationFailed: any(named: 'verificationFailed'),
          codeSent: any(named: 'codeSent'),
          codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
        ),
      ).thenAnswer((invocation) async {
        final callbacks = invocation.namedArguments;
        if (autoVerified != null) {
          (callbacks[#verificationCompleted]
              as void Function(PhoneAuthCredential))(autoVerified);
        } else if (codeSentId != null) {
          (callbacks[#codeSent] as void Function(String, int?))(codeSentId, 1);
        } else if (verificationIdOnTimeout != null) {
          (callbacks[#codeAutoRetrievalTimeout] as void Function(String))(
            verificationIdOnTimeout,
          );
        } else if (failure != null) {
          (callbacks[#verificationFailed]
              as void Function(FirebaseAuthException))(failure);
        }
        if (thenCodeSentId != null) {
          (callbacks[#codeSent] as void Function(String, int?))(
            thenCodeSentId,
            null,
          );
        }
      });
    }

    test(
      'returns the platform credential when the device verifies itself',
      () async {
        // ARRANGE: Android instant verification — no SMS is sent.
        final credential = PhoneAuthProvider.credential(
          verificationId: 'instant-verification-id',
          smsCode: '123456',
        );
        simulatePlatform(autoVerified: credential);

        final service = AuthService(auth: mockAuth, isWeb: false);

        // ACT
        final result = await service.startPhoneVerification(phoneNumber);

        // ASSERT
        expect(
          result,
          isA<PhoneVerificationAutoVerified>().having(
            (verification) => verification.credential,
            'credential',
            same(credential),
          ),
        );
      },
    );

    test('returns the verification id when a code was sent', () async {
      // ARRANGE
      const verificationId = 'sms-verification-id';
      simulatePlatform(codeSentId: verificationId);

      final service = AuthService(auth: mockAuth, isWeb: false);

      // ACT
      final result = await service.startPhoneVerification(phoneNumber);

      // ASSERT
      expect(
        result,
        isA<PhoneVerificationCodeSent>().having(
          (verification) => verification.verificationId,
          'verificationId',
          verificationId,
        ),
      );
    });

    test('treats an auto-retrieval timeout as a code that was sent', () async {
      // ARRANGE
      const verificationId = 'timeout-verification-id';
      simulatePlatform(verificationIdOnTimeout: verificationId);

      final service = AuthService(auth: mockAuth, isWeb: false);

      // ACT
      final result = await service.startPhoneVerification(phoneNumber);

      // ASSERT
      expect(
        result,
        isA<PhoneVerificationCodeSent>().having(
          (verification) => verification.verificationId,
          'verificationId',
          verificationId,
        ),
      );
    });

    test('propagates a verification failure', () async {
      // ARRANGE
      final failure = FirebaseAuthException(
        code: 'invalid-phone-number',
        message: 'bad number',
      );
      simulatePlatform(failure: failure);

      final service = AuthService(auth: mockAuth, isWeb: false);

      // ACT & ASSERT
      await expectLater(
        service.startPhoneVerification(phoneNumber),
        throwsA(same(failure)),
      );
    });

    test('keeps the first result when the platform reports twice', () async {
      // ARRANGE: instant verification fires, then a code is reported as sent.
      final credential = PhoneAuthProvider.credential(
        verificationId: 'instant-verification-id',
        smsCode: '123456',
      );
      simulatePlatform(autoVerified: credential, thenCodeSentId: 'late-code');

      final service = AuthService(auth: mockAuth, isWeb: false);

      // ACT
      final result = await service.startPhoneVerification(phoneNumber);

      // ASSERT: the second report must not try to complete the future again.
      expect(
        result,
        isA<PhoneVerificationAutoVerified>().having(
          (verification) => verification.credential,
          'credential',
          same(credential),
        ),
      );
    });

    test('times out when the platform never reports', () async {
      // ARRANGE: the platform invokes no callback at all.
      simulatePlatform();

      final service = AuthService(auth: mockAuth, isWeb: false);

      // ACT & ASSERT
      await expectLater(
        service.startPhoneVerification(
          phoneNumber,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test(
      'on web, starts the reCAPTCHA flow and returns its verification id',
      () async {
        // ARRANGE
        const verificationId = 'web-verification-id';
        final confirmationResult = MockConfirmationResult();
        when(() => mockAuth.signInWithPhoneNumber(any()))
            .thenAnswer((_) async => confirmationResult);
        when(() => confirmationResult.verificationId)
            .thenReturn(verificationId);

        final service = AuthService(auth: mockAuth, isWeb: true);

        // ACT
        final result = await service.startPhoneVerification(phoneNumber);

        // ASSERT
        expect(
          result,
          isA<PhoneVerificationCodeSent>().having(
            (verification) => verification.verificationId,
            'verificationId',
            verificationId,
          ),
        );
      },
    );
  });

  group('AuthService.reauthenticateWithPhoneCredential', () {
    test('reauthenticates with the credential the platform verified', () async {
      // ARRANGE
      final user = MockUser();
      final credential = PhoneAuthProvider.credential(
        verificationId: 'instant-verification-id',
        smsCode: '123456',
      );
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());

      final service = AuthService(auth: mockAuth);

      // ACT
      await service.reauthenticateWithPhoneCredential(credential);

      // ASSERT
      final captured =
          verify(() => user.reauthenticateWithCredential(captureAny()))
                  .captured
                  .single
              as PhoneAuthCredential;
      expect(captured.verificationId, credential.verificationId);
      expect(captured.smsCode, credential.smsCode);
    });
  });
}
