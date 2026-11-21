import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/phone_verification.dart';

import '../../../core/logging/recording_sink.dart';
import '../../../core/logging/wire_absence.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockConfirmationResult extends Mock implements ConfirmationResult {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockUserInfo extends Mock implements UserInfo {}

class MockIdTokenResult extends Mock implements IdTokenResult {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

const String googleIdToken = 'google-id-token';

/// A Google account whose authentication carries [idToken].
MockGoogleSignInAccount googleAccount({String? idToken = googleIdToken}) {
  final account = MockGoogleSignInAccount();
  when(() => account.authentication)
      .thenReturn(GoogleSignInAuthentication(idToken: idToken));
  return account;
}

/// Stubs the one-shot initialization every Google flow awaits.
void stubGoogleInitialization(MockGoogleSignIn googleSignIn) {
  when(
    () => googleSignIn.initialize(
      clientId: any(named: 'clientId'),
      serverClientId: any(named: 'serverClientId'),
    ),
  ).thenAnswer((_) async {});
}

/// A signed-in user whose account links Google and deletes cleanly.
MockUser googleLinkedUser(MockFirebaseAuth auth) {
  final user = MockUser();
  final info = MockUserInfo();
  when(() => info.providerId).thenReturn('google.com');
  when(() => auth.currentUser).thenReturn(user);
  when(() => user.providerData).thenReturn(<UserInfo>[info]);
  when(() => user.delete()).thenAnswer((_) async {});
  return user;
}

/// Asserts [captured] is the idToken-only Firebase Google credential.
void expectGoogleIdTokenOnly(Object? captured) {
  final credential = captured! as OAuthCredential;
  expect(credential.providerId, 'google.com');
  expect(credential.idToken, googleIdToken);
  expect(credential.accessToken, isNull);
}

/// A web service already listening to a controllable Google event stream.
Future<
  ({
    AuthService service,
    StreamController<GoogleSignInAuthenticationEvent> events,
  })
>
preparedWebGoogleService(
  MockFirebaseAuth auth,
  MockGoogleSignIn googleSignIn,
) async {
  final events = StreamController<GoogleSignInAuthenticationEvent>.broadcast();
  addTearDown(events.close);
  stubGoogleInitialization(googleSignIn);
  when(() => googleSignIn.authenticationEvents)
      .thenAnswer((_) => events.stream);
  final service = AuthService(
    auth: auth,
    isWeb: true,
    googleSignIn: googleSignIn,
  );
  await service.prepareGoogleSignIn();
  return (service: service, events: events);
}

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

    test(
      'on web, a confirmed sign-in leaves nothing to confirm again',
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
        await authService.confirmPhoneCode(
          verificationId: verificationId,
          smsCode: smsCode,
        );

        // Act
        final secondConfirmation = authService.confirmPhoneCode(
          verificationId: verificationId,
          smsCode: smsCode,
        );

        // Assert
        await expectLater(secondConfirmation, throwsStateError);
        verify(() => confirmationResult.confirm(smsCode)).called(1);
      },
    );

    test('on web, a rejected code can be retried', () async {
      // Arrange
      const phoneNumber = '+15550001111';
      const rejection = '000000';
      const retry = '654321';
      final confirmationResult = MockConfirmationResult();
      final userCredential = MockUserCredential();
      when(() => mockAuth.signInWithPhoneNumber(phoneNumber))
          .thenAnswer((_) async => confirmationResult);
      when(() => confirmationResult.verificationId)
          .thenReturn('web-verification-id');
      when(() => confirmationResult.confirm(rejection))
          .thenThrow(FirebaseAuthException(code: 'invalid-verification-code'));
      when(() => confirmationResult.confirm(retry))
          .thenAnswer((_) async => userCredential);
      final authService = AuthService(auth: mockAuth, isWeb: true);
      final verificationId = await authService.startWebPhoneSignIn(phoneNumber);
      await expectLater(
        authService.confirmPhoneCode(
          verificationId: verificationId,
          smsCode: rejection,
        ),
        throwsA(isA<FirebaseAuthException>()),
      );

      // Act
      final result = await authService.confirmPhoneCode(
        verificationId: verificationId,
        smsCode: retry,
      );

      // Assert
      expect(result, same(userCredential));
    });
  });

  group('AuthService.discardPendingPhoneSignIn', () {
    test(
      'stops a later confirmation reusing the abandoned web sign-in',
      () async {
        // Arrange
        const phoneNumber = '+15550001111';
        const smsCode = '654321';
        final confirmationResult = MockConfirmationResult();
        when(() => mockAuth.signInWithPhoneNumber(phoneNumber))
            .thenAnswer((_) async => confirmationResult);
        when(() => confirmationResult.verificationId)
            .thenReturn('web-verification-id');
        final authService = AuthService(auth: mockAuth, isWeb: true);
        final verificationId = await authService.startWebPhoneSignIn(
          phoneNumber,
        );
        authService.discardPendingPhoneSignIn();

        // Act
        final confirmation = authService.confirmPhoneCode(
          verificationId: verificationId,
          smsCode: smsCode,
        );

        // Assert
        await expectLater(confirmation, throwsStateError);
        verifyNever(() => confirmationResult.confirm(any()));
      },
    );
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

  group('AuthService Google initialization', () {
    test('initializes the plugin once across services sharing it', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      stubGoogleInitialization(googleSignIn);
      final first = AuthService(auth: mockAuth, googleSignIn: googleSignIn);
      final second = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // ACT
      await first.prepareGoogleSignIn();
      await second.prepareGoogleSignIn();

      // ASSERT
      verify(
        () => googleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      ).called(1);
    });

    test(
      'on web, keeps the client id even when the browser runs on iOS',
      () async {
        // ARRANGE: iOS Safari reports defaultTargetPlatform.iOS on web.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final googleSignIn = MockGoogleSignIn();
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.authenticationEvents).thenAnswer(
          (_) => const Stream<GoogleSignInAuthenticationEvent>.empty(),
        );
        final service = AuthService(
          auth: mockAuth,
          isWeb: true,
          googleSignIn: googleSignIn,
        );

        // ACT
        await service.prepareGoogleSignIn();

        // ASSERT
        verify(
          () => googleSignIn.initialize(
            clientId: AuthService.clientId,
            serverClientId: null,
          ),
        ).called(1);
      },
    );

    test(
      'on iOS, passes no ids so the bundled plist supplies the client',
      () async {
        // ARRANGE
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final googleSignIn = MockGoogleSignIn();
        stubGoogleInitialization(googleSignIn);
        final service = AuthService(
          auth: mockAuth,
          isWeb: false,
          googleSignIn: googleSignIn,
        );

        // ACT
        await service.prepareGoogleSignIn();

        // ASSERT
        verify(
          () => googleSignIn.initialize(clientId: null, serverClientId: null),
        ).called(1);
      },
    );

    test('on Android, passes the web client as the server client id', () async {
      // ARRANGE
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final googleSignIn = MockGoogleSignIn();
      stubGoogleInitialization(googleSignIn);
      final service = AuthService(
        auth: mockAuth,
        isWeb: false,
        googleSignIn: googleSignIn,
      );

      // ACT
      await service.prepareGoogleSignIn();

      // ASSERT
      verify(
        () => googleSignIn.initialize(
          clientId: null,
          serverClientId: AuthService.clientId,
        ),
      ).called(1);
    });
  });

  group('AuthService.signInWithGoogle', () {
    test('exchanges the native idToken for a Firebase session', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      final userCredential = MockUserCredential();
      final account = googleAccount();
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.authenticate()).thenAnswer((_) async => account);
      when(() => mockAuth.signInWithCredential(any()))
          .thenAnswer((_) async => userCredential);
      final service = AuthService(
        auth: mockAuth,
        isWeb: false,
        googleSignIn: googleSignIn,
      );

      // ACT
      final result = await service.signInWithGoogle();

      // ASSERT: initialization completes before the interactive call, and v7
      // authentication carries no access token.
      expect(result, same(userCredential));
      verifyInOrder([
        () => googleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
        () => googleSignIn.authenticate(),
      ]);
      expectGoogleIdTokenOnly(
        verify(() => mockAuth.signInWithCredential(captureAny()))
            .captured
            .single,
      );
    });

    test('on web, refuses the native path with a typed failure', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      final service = AuthService(
        auth: mockAuth,
        isWeb: true,
        googleSignIn: googleSignIn,
      );

      // ACT & ASSERT
      await expectLater(
        service.signInWithGoogle(),
        throwsA(
          isA<GoogleSignInException>().having(
            (error) => error.code,
            'code',
            GoogleSignInExceptionCode.uiUnavailable,
          ),
        ),
      );
      verifyNever(() => googleSignIn.authenticate());
    });

    test('on web, exchanges a sign-in event for a Firebase session', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      final userCredential = MockUserCredential();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.signInWithCredential(any()))
          .thenAnswer((_) async => userCredential);
      final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);

      // ACT
      prepared.events.add(
        GoogleSignInAuthenticationEventSignIn(user: googleAccount()),
      );
      await pumpEventQueue();

      // ASSERT
      expectGoogleIdTokenOnly(
        verify(() => mockAuth.signInWithCredential(captureAny()))
            .captured
            .single,
      );
    });

    test('on web, ignores a sign-in event while a user is signed in', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      when(() => mockAuth.currentUser).thenReturn(MockUser());
      final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);

      // ACT
      prepared.events.add(
        GoogleSignInAuthenticationEventSignIn(user: googleAccount()),
      );
      await pumpEventQueue();

      // ASSERT
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });

    test('one plugin instance owns a single web subscription', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.signInWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());
      final first = await preparedWebGoogleService(mockAuth, googleSignIn);
      final second = AuthService(
        auth: mockAuth,
        isWeb: true,
        googleSignIn: googleSignIn,
      );
      await second.prepareGoogleSignIn();

      // ACT
      first.events.add(
        GoogleSignInAuthenticationEventSignIn(user: googleAccount()),
      );
      await pumpEventQueue();

      // ASSERT: one event, one exchange, one initialization.
      verify(() => mockAuth.signInWithCredential(any())).called(1);
      verify(
        () => googleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      ).called(1);
    });

    test('on web, ignores a sign-out event', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      // ACT
      prepared.events.add(GoogleSignInAuthenticationEventSignOut());
      await pumpEventQueue();

      // ASSERT: only sign-in events carry a credential; a sign-out event must
      // not exchange anything or touch the Firebase session.
      verifyNever(() => mockAuth.signInWithCredential(any()));
      verifyNever(() => mockAuth.signOut());
    });
  });

  group('AuthService.signOut', () {
    test('signs out of Google before Firebase once initialized', () async {
      // ARRANGE
      final googleSignIn = MockGoogleSignIn();
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);
      await service.prepareGoogleSignIn();

      // ACT
      await service.signOut();

      // ASSERT
      verifyInOrder([() => googleSignIn.signOut(), () => mockAuth.signOut()]);
    });

    test('does not wait for a pending Google initialization', () async {
      // ARRANGE: the GIS SDK never finishes loading.
      final googleSignIn = MockGoogleSignIn();
      final pending = Completer<void>();
      when(
        () => googleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      ).thenAnswer((_) => pending.future);
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);
      unawaited(service.prepareGoogleSignIn());

      // ACT
      await service.signOut();

      // ASSERT: Firebase is cleared without waiting on a hung third party.
      verify(() => mockAuth.signOut()).called(1);
      verifyNever(() => googleSignIn.signOut());
      pending.complete();
      await pumpEventQueue();
    });

    test(
      'still signs out of Firebase after a failed Google initialization',
      () async {
        // ARRANGE
        final googleSignIn = MockGoogleSignIn();
        when(
          () => googleSignIn.initialize(
            clientId: any(named: 'clientId'),
            serverClientId: any(named: 'serverClientId'),
          ),
        ).thenThrow(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
          ),
        );
        when(() => mockAuth.signOut()).thenAnswer((_) async {});
        final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);
        await expectLater(
          service.prepareGoogleSignIn(),
          throwsA(isA<GoogleSignInException>()),
        );

        // ACT
        await service.signOut();

        // ASSERT
        verify(() => mockAuth.signOut()).called(1);
        verifyNever(() => googleSignIn.signOut());
      },
    );
  });

  group('AuthService.deleteAccount', () {
    test(
      'deletes the auth user and then revokes a linked Google grant',
      () async {
        // ARRANGE
        final googleSignIn = MockGoogleSignIn();
        final user = googleLinkedUser(mockAuth);
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.disconnect()).thenAnswer((_) async {});

        final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

        // ACT
        await service.deleteAccount();

        // ASSERT: disconnect revokes the provider grant; signOut only drops the
        // local session and would leave the app listed on the Google account.
        verifyInOrder([() => user.delete(), () => googleSignIn.disconnect()]);
        verifyNever(() => googleSignIn.signOut());
      },
    );

    test('does not touch Google when the account has no Google link', () async {
      // ARRANGE
      final user = MockUser();
      final googleSignIn = MockGoogleSignIn();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => user.providerData).thenReturn(<UserInfo>[]);
      when(() => user.delete()).thenAnswer((_) async {});
      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // ACT
      await service.deleteAccount();

      // ASSERT
      verify(() => user.delete()).called(1);
      verifyNever(
        () => googleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      );
      verifyNever(() => googleSignIn.disconnect());
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
      final googleSignIn = MockGoogleSignIn();
      googleLinkedUser(mockAuth);
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.disconnect())
          .thenThrow(Exception('google unavailable'));

      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // ACT & ASSERT: the deletion already happened, so it must not be
      // reported as a failure.
      await expectLater(service.deleteAccount(), completes);
    });
  });

  group('AuthService.reauthenticateWithGoogle', () {
    test(
      'on native, reauthenticates with a fresh idToken-only Google credential',
      () async {
        // ARRANGE
        final user = MockUser();
        final googleSignIn = MockGoogleSignIn();
        when(() => mockAuth.currentUser).thenReturn(user);
        final account = googleAccount();
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.authenticate())
            .thenAnswer((_) async => account);
        when(() => user.reauthenticateWithCredential(any()))
            .thenAnswer((_) async => MockUserCredential());

        final service = AuthService(
          auth: mockAuth,
          isWeb: false,
          googleSignIn: googleSignIn,
        );

        // ACT
        await service.reauthenticateWithGoogle();

        // ASSERT: initialization completes before the interactive call, and v7
        // authentication carries no access token.
        verifyInOrder([
          () => googleSignIn.initialize(
            clientId: any(named: 'clientId'),
            serverClientId: any(named: 'serverClientId'),
          ),
          () => googleSignIn.authenticate(),
        ]);
        expectGoogleIdTokenOnly(
          verify(() => user.reauthenticateWithCredential(captureAny()))
              .captured
              .single,
        );
      },
    );

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
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.authenticate()).thenThrow(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        );

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

  group('AuthService.uidChanges', () {
    test('emits the signed-in uid and null on sign-out', () async {
      // ARRANGE
      final changes = StreamController<User?>();
      addTearDown(changes.close);
      when(() => mockAuth.authStateChanges()).thenAnswer((_) => changes.stream);
      const uid = 'uid-1';
      final user = MockUser();
      when(() => user.uid).thenReturn(uid);
      final service = AuthService(auth: mockAuth);
      final seen = <String?>[];
      final subscription = service.uidChanges.listen(seen.add);
      addTearDown(subscription.cancel);

      // ACT
      changes.add(user);
      changes.add(null);
      await pumpEventQueue();

      // ASSERT
      expect(seen, [uid, null]);
    });
  });

  group('AuthService.supportsAccountDeletion', () {
    test('keeps in-app account deletion available in production', () {
      // ARRANGE
      final service = AuthService(auth: mockAuth);

      // ACT & ASSERT
      expect(service.supportsAccountDeletion, isTrue);
    });
  });

  group('AuthService.supportsSignOut', () {
    test('offers sign-out in production', () {
      // ARRANGE
      final service = AuthService(auth: mockAuth);

      // ACT & ASSERT
      expect(service.supportsSignOut, isTrue);
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

  group('AuthService diagnostics', () {
    late RecordingSink sink;

    setUp(() async {
      await getIt.reset();
      sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
    });

    tearDown(getIt.reset);

    test('reports a failed Apple sign-in with its code', () async {
      const missingTokenCode = appleMissingIdTokenCode;
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
              authorizationCode: 'code',
              email: null,
              identityToken: null,
              state: null,
            ),
      );

      await expectLater(
        service.signInWithApple(),
        throwsA(isA<FirebaseAuthException>()),
      );

      final event = sink.eventsOf<AuthStateEvent>().single;
      expect(event.outcome, AuthOutcome.apple);
      expect(event.code, missingTokenCode);
    });

    test('reports a failed web phone request with its code', () async {
      const code = 'invalid-phone-number';
      when(() => mockAuth.signInWithPhoneNumber(any()))
          .thenThrow(FirebaseAuthException(code: code));
      final service = AuthService(auth: mockAuth, isWeb: true);

      await expectLater(
        service.startWebPhoneSignIn('+15550001111'),
        throwsA(isA<FirebaseAuthException>()),
      );

      final event = sink.eventsOf<AuthStateEvent>().single;
      expect(event.outcome, AuthOutcome.phone);
      expect(event.code, code);
    });

    test(
      'keeps a cancelled web phone prompt out of the warning family',
      () async {
        const code = 'web-context-canceled';
        when(() => mockAuth.signInWithPhoneNumber(any()))
            .thenThrow(FirebaseAuthException(code: code));
        final service = AuthService(auth: mockAuth, isWeb: true);

        await expectLater(
          service.startWebPhoneSignIn('+15550001111'),
          throwsA(isA<FirebaseAuthException>()),
        );

        final event = sink.eventsOf<AuthStateEvent>().single;
        expect(event.outcome, AuthOutcome.phone);
        expect(event.code, isNull);
      },
    );

    test('reports a failed phone-code confirmation with its code', () async {
      const code = 'invalid-verification-code';
      when(() => mockAuth.signInWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: code));
      final service = AuthService(auth: mockAuth, isWeb: false);

      await expectLater(
        service.confirmPhoneCode(
          verificationId: 'verification-id',
          smsCode: '000000',
        ),
        throwsA(isA<FirebaseAuthException>()),
      );

      final event = sink.eventsOf<AuthStateEvent>().single;
      expect(event.outcome, AuthOutcome.phone);
      expect(event.code, code);
    });

    test('reports a native phone verification failure with its code', () async {
      const code = 'invalid-phone-number';
      when(
        () => mockAuth.verifyPhoneNumber(
          phoneNumber: any(named: 'phoneNumber'),
          verificationCompleted: any(named: 'verificationCompleted'),
          verificationFailed: any(named: 'verificationFailed'),
          codeSent: any(named: 'codeSent'),
          codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
        ),
      ).thenAnswer((invocation) async {
        final failed =
            invocation.namedArguments[#verificationFailed]
                as void Function(FirebaseAuthException);
        failed(FirebaseAuthException(code: code));
      });
      final service = AuthService(auth: mockAuth, isWeb: false);

      await service.verifyPhoneNumber(
        phoneNumber: '+15550001111',
        verificationCompleted: (_) {},
        verificationFailed: (_) {},
        codeSent: (_, _) {},
        codeAutoRetrievalTimeout: (_) {},
      );

      final event = sink.eventsOf<AuthStateEvent>().single;
      expect(event.outcome, AuthOutcome.phone);
      expect(event.code, code);
    });

    test('counts a failure reported through both phone paths once', () async {
      final failure = FirebaseAuthException(code: 'invalid-phone-number');
      when(
        () => mockAuth.verifyPhoneNumber(
          phoneNumber: any(named: 'phoneNumber'),
          verificationCompleted: any(named: 'verificationCompleted'),
          verificationFailed: any(named: 'verificationFailed'),
          codeSent: any(named: 'codeSent'),
          codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
        ),
      ).thenAnswer((invocation) async {
        final failed =
            invocation.namedArguments[#verificationFailed]
                as void Function(FirebaseAuthException);
        failed(failure);
        throw failure;
      });
      final service = AuthService(auth: mockAuth, isWeb: false);

      await expectLater(
        service.verifyPhoneNumber(
          phoneNumber: '+15550001111',
          verificationCompleted: (_) {},
          verificationFailed: (_) {},
          codeSent: (_, _) {},
          codeAutoRetrievalTimeout: (_) {},
        ),
        throwsA(same(failure)),
      );

      expect(sink.eventsOf<AuthStateEvent>(), hasLength(1));
    });

    test(
      'reports one failure when the native verification times out',
      () async {
        // Arrange: the platform never invokes a callback.
        when(
          () => mockAuth.verifyPhoneNumber(
            phoneNumber: any(named: 'phoneNumber'),
            verificationCompleted: any(named: 'verificationCompleted'),
            verificationFailed: any(named: 'verificationFailed'),
            codeSent: any(named: 'codeSent'),
            codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
          ),
        ).thenAnswer((_) async {});
        final service = AuthService(auth: mockAuth, isWeb: false);

        // Act & Assert
        await expectLater(
          service.startPhoneVerification(
            '+15550001111',
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<TimeoutException>()),
        );

        final event = sink.eventsOf<AuthStateEvent>().single;
        expect(event.outcome, AuthOutcome.phone);
        expect(event.code, 'timeout');
      },
    );

    test(
      'keeps a cancelled native Google sign-in out of the warning family',
      () async {
        // Arrange
        final googleSignIn = MockGoogleSignIn();
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.authenticate()).thenThrow(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        );
        final service = AuthService(
          auth: mockAuth,
          isWeb: false,
          googleSignIn: googleSignIn,
        );

        // Act & Assert
        await expectLater(
          service.signInWithGoogle(),
          throwsA(isA<GoogleSignInException>()),
        );

        // Assert: the outcome survives, the cancellation is not a failure code.
        final event = sink.eventsOf<AuthStateEvent>().single;
        expect(event.outcome, AuthOutcome.google);
        expect(event.code, isNull);
      },
    );

    test('reports a native Google failure with a kebab-case code', () async {
      // Arrange
      final googleSignIn = MockGoogleSignIn();
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      );
      final service = AuthService(
        auth: mockAuth,
        isWeb: false,
        googleSignIn: googleSignIn,
      );

      // Act & Assert
      await expectLater(
        service.signInWithGoogle(),
        throwsA(isA<GoogleSignInException>()),
      );

      // Assert
      final event = sink.eventsOf<AuthStateEvent>().single;
      expect(event.outcome, AuthOutcome.google);
      expect(event.code, 'client-configuration-error');
    });

    test('records one warning when Google returns no id token', () async {
      // Arrange
      final googleSignIn = MockGoogleSignIn();
      final account = googleAccount(idToken: null);
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.authenticate()).thenAnswer((_) async => account);
      when(() => googleSignIn.signOut()).thenAnswer((_) async {});
      final service = AuthService(
        auth: mockAuth,
        isWeb: false,
        googleSignIn: googleSignIn,
      );

      // Act & Assert
      await expectLater(
        service.signInWithGoogle(),
        throwsA(isA<GoogleSignInException>()),
      );

      // Assert: a warning, not an AssertionError breadcrumb, and no exchange.
      expect(sink.eventsOf<AuthStateEvent>().single.code, 'unknown-error');
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });

    test(
      'records one warning when reauthentication gets no id token',
      () async {
        // Arrange
        final user = MockUser();
        final googleSignIn = MockGoogleSignIn();
        when(() => mockAuth.currentUser).thenReturn(user);
        final account = googleAccount(idToken: null);
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.authenticate())
            .thenAnswer((_) async => account);
        final service = AuthService(
          auth: mockAuth,
          isWeb: false,
          googleSignIn: googleSignIn,
        );

        // Act & Assert
        await expectLater(
          service.reauthenticateWithGoogle(),
          throwsA(isA<GoogleSignInException>()),
        );

        // Assert
        expect(sink.eventsOf<AuthStateEvent>().single.code, 'unknown-error');
        verifyNever(() => user.reauthenticateWithCredential(any()));
      },
    );

    test(
      'keeps a web access_denied response out of the warning family',
      () async {
        // Arrange
        final googleSignIn = MockGoogleSignIn();
        final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);

        // Act
        prepared.events.addError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'access_denied',
          ),
        );
        await pumpEventQueue();

        // Assert
        final event = sink.eventsOf<AuthStateEvent>().single;
        expect(event.outcome, AuthOutcome.google);
        expect(event.code, isNull);
      },
    );

    test(
      'keeps a web popup_closed_by_user out of the warning family',
      () async {
        // Arrange
        final googleSignIn = MockGoogleSignIn();
        final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);

        // Act
        prepared.events.addError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'popup_closed_by_user',
          ),
        );
        await pumpEventQueue();

        // Assert
        expect(sink.eventsOf<AuthStateEvent>().single.code, isNull);
      },
    );

    test('reports a web Google failure with a kebab-case code', () async {
      // Arrange
      final googleSignIn = MockGoogleSignIn();
      final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);

      // Act
      prepared.events.addError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      );
      await pumpEventQueue();

      // Assert
      expect(
        sink.eventsOf<AuthStateEvent>().single.code,
        'client-configuration-error',
      );
    });

    test('a failing Google cleanup does not replace the sign-in failure', () async {
      // Arrange: the Firebase exchange fails, then the cleanup sign-out fails.
      final googleSignIn = MockGoogleSignIn();
      final account = googleAccount();
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.authenticate()).thenAnswer((_) async => account);
      when(() => mockAuth.signInWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));
      when(() => googleSignIn.signOut())
          .thenThrow(StateError('cleanup failed'));
      final service = AuthService(
        auth: mockAuth,
        isWeb: false,
        googleSignIn: googleSignIn,
      );

      // Act & Assert
      await expectLater(
        service.signInWithGoogle(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'invalid-credential',
          ),
        ),
      );

      // Assert: one sign-in warning and one cleanup error; the original wins.
      expect(sink.eventsOf<AuthStateEvent>().single.code, 'invalid-credential');
      expect(sink.eventsOf<ErrorEvent>().single.code, 'google-sign-out-failed');
    });

    test(
      'reports a failed web exchange and drops the Google session',
      () async {
        // Arrange
        final googleSignIn = MockGoogleSignIn();
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockAuth.signInWithCredential(any()))
            .thenThrow(FirebaseAuthException(code: 'invalid-credential'));
        when(() => googleSignIn.signOut()).thenAnswer((_) async {});
        final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);

        // Act
        prepared.events.add(
          GoogleSignInAuthenticationEventSignIn(user: googleAccount()),
        );
        await pumpEventQueue();

        // Assert
        expect(
          sink.eventsOf<AuthStateEvent>().single.code,
          'invalid-credential',
        );
        verify(() => googleSignIn.signOut()).called(1);
      },
    );

    test('records one warning when a web event has no idToken', () async {
      // Arrange
      final googleSignIn = MockGoogleSignIn();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => googleSignIn.signOut()).thenAnswer((_) async {});
      final prepared = await preparedWebGoogleService(mockAuth, googleSignIn);
      final account = googleAccount(idToken: null);

      // Act
      prepared.events.add(GoogleSignInAuthenticationEventSignIn(user: account));
      await pumpEventQueue();

      // Assert: a warning, not AssertionError-shaped breadcrumb, and no
      // credential exchange.
      expect(sink.eventsOf<AuthStateEvent>().single.code, 'unknown-error');
      verifyNever(() => mockAuth.signInWithCredential(any()));
      verify(() => googleSignIn.signOut()).called(1);
    });

    test('logs one initialization failure across services', () async {
      // Arrange
      final googleSignIn = MockGoogleSignIn();
      when(
        () => googleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      ).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      );
      final first = AuthService(auth: mockAuth, googleSignIn: googleSignIn);
      final second = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // Act & Assert
      await expectLater(
        first.prepareGoogleSignIn(),
        throwsA(isA<GoogleSignInException>()),
      );
      await expectLater(
        second.prepareGoogleSignIn(),
        throwsA(isA<GoogleSignInException>()),
      );

      // Assert: the shared future logs the process failure once.
      final errors = sink.eventsOf<ErrorEvent>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, 'google-sign-in-init-failed');
    });

    test('counts a timeout and a late platform failure once', () async {
      // Arrange: the platform reports its failure only after the bound fired.
      final failure = FirebaseAuthException(code: 'invalid-phone-number');
      when(
        () => mockAuth.verifyPhoneNumber(
          phoneNumber: any(named: 'phoneNumber'),
          verificationCompleted: any(named: 'verificationCompleted'),
          verificationFailed: any(named: 'verificationFailed'),
          codeSent: any(named: 'codeSent'),
          codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
        ),
      ).thenAnswer((invocation) async {
        final failed =
            invocation.namedArguments[#verificationFailed]
                as void Function(FirebaseAuthException);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        failed(failure);
      });
      final service = AuthService(auth: mockAuth, isWeb: false);

      // Act: time out first ...
      await expectLater(
        service.startPhoneVerification(
          '+15550001111',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
      // ... then let the late platform failure arrive.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Assert: one failure for the attempt, and it is the timeout's.
      final event = sink.eventsOf<AuthStateEvent>().single;
      expect(event.code, 'timeout');
    });

    test(
      'a failed phone sign-in reports no identifier or message text',
      () async {
        // Arrange: the exception text carries every shape the wire must not.
        const phoneNumber = '+15555550123';
        const itemId = 'item-7f3a9c1d2e';
        const updateMessageToken = 'MAINTENANCE-WINDOW-42';
        when(() => mockAuth.signInWithPhoneNumber(any())).thenThrow(
          FirebaseAuthException(
            code: 'invalid-phone-number',
            message:
                'The number $phoneNumber failed, item $itemId, '
                'message $updateMessageToken',
          ),
        );
        final service = AuthService(auth: mockAuth, isWeb: true);

        // Act
        await expectLater(
          service.startWebPhoneSignIn(phoneNumber),
          throwsA(isA<FirebaseAuthException>()),
        );

        // Assert: checked at the emitter too — the wire redactor would drop a
        // raw message that reached the code, hiding exactly this leak.
        expect(
          sink.eventsOf<AuthStateEvent>().single.code,
          'invalid-phone-number',
        );
        expectNoSensitiveValues(sink.records, <String>[
          phoneNumber,
          itemId,
          updateMessageToken,
        ]);
      },
    );

    test('reports a failed Google revocation after deletion', () async {
      // Arrange
      final googleSignIn = MockGoogleSignIn();
      googleLinkedUser(mockAuth);
      stubGoogleInitialization(googleSignIn);
      when(() => googleSignIn.disconnect())
          .thenThrow(StateError('revocation failed'));
      final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

      // Act
      await service.deleteAccount();

      // Assert
      final event = sink.records.single.event;
      expect(event, isA<ErrorEvent>());
      expect((event as ErrorEvent).code, 'google-revoke-failed');
    });

    test(
      'logs a bounded Google revocation and completes the deletion',
      () async {
        // Arrange: a Google link exists but the SDK never finishes loading.
        final googleSignIn = MockGoogleSignIn();
        final user = googleLinkedUser(mockAuth);
        final pending = Completer<void>();
        when(
          () => googleSignIn.initialize(
            clientId: any(named: 'clientId'),
            serverClientId: any(named: 'serverClientId'),
          ),
        ).thenAnswer((_) => pending.future);
        final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

        // Act
        await service.deleteAccount(
          googleRevokeTimeout: const Duration(milliseconds: 10),
        );

        // Assert: the deletion is what mattered; the revocation never ran.
        verify(() => user.delete()).called(1);
        verifyNever(() => googleSignIn.disconnect());
        expect(sink.eventsOf<ErrorEvent>().single.code, 'google-revoke-failed');
        pending.complete();
        await pumpEventQueue();
      },
    );

    test(
      'bounds a hanging Google disconnect and completes the deletion',
      () async {
        // Arrange: initialization succeeds, but disconnect never returns.
        final googleSignIn = MockGoogleSignIn();
        final user = googleLinkedUser(mockAuth);
        final pending = Completer<void>();
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.disconnect()).thenAnswer((_) => pending.future);
        final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);

        // Act
        await service.deleteAccount(
          googleRevokeTimeout: const Duration(milliseconds: 10),
        );

        // Assert
        verify(() => user.delete()).called(1);
        expect(sink.eventsOf<ErrorEvent>().single.code, 'google-revoke-failed');
        pending.complete();
        await pumpEventQueue();
      },
    );

    test('leaves the sign-out outcome to the auth listener', () async {
      // Arrange: no Google flow ran, so there is no Google session to drop.
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      final service = AuthService(auth: mockAuth);

      // Act
      await service.signOut();

      // Assert
      expect(sink.records, isEmpty);
    });

    test(
      'logs a Google sign-out failure and still signs out of Firebase',
      () async {
        // Arrange
        final googleSignIn = MockGoogleSignIn();
        stubGoogleInitialization(googleSignIn);
        when(() => googleSignIn.signOut())
            .thenThrow(StateError('google unavailable'));
        when(() => mockAuth.signOut()).thenAnswer((_) async {});
        final service = AuthService(auth: mockAuth, googleSignIn: googleSignIn);
        await service.prepareGoogleSignIn();

        // Act
        await service.signOut();

        // Assert: the credential is gone even though Google failed.
        verify(() => mockAuth.signOut()).called(1);
        expect(
          sink.eventsOf<ErrorEvent>().single.code,
          'google-sign-out-failed',
        );
      },
    );
  });
}
