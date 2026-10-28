import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_log.dart';

import '../../../core/logging/recording_sink.dart';

import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';

class MockAuthService extends Mock implements AuthService {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

void main() {
  group('shouldShowAppleSignInButton', () {
    test('shows on native iOS', () {
      expect(
        shouldShowAppleSignInButton(isWeb: false, platform: TargetPlatform.iOS),
        isTrue,
      );
    });

    test('hides on iOS Safari, where web resolves to the browser OS', () {
      expect(
        shouldShowAppleSignInButton(isWeb: true, platform: TargetPlatform.iOS),
        isFalse,
      );
    });

    test('hides on Android', () {
      expect(
        shouldShowAppleSignInButton(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('hides on web regardless of the browser OS', () {
      expect(
        shouldShowAppleSignInButton(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('hides on macOS', () {
      expect(
        shouldShowAppleSignInButton(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
    });
  });

  group('LoginPage support code', () {
    setUp(() async {
      await getIt.reset();
      getIt.registerSingleton<AuthService>(MockAuthService());
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: const []),
      );
    });

    tearDown(getIt.reset);

    testWidgets('shows the support code to a signed-out user', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pump();

      expect(find.text(testSession.supportCode), findsOneWidget);
    });
  });

  group('LoginPage sign-in failures', () {
    late MockAuthService authService;
    late MockGoogleSignIn googleSignIn;

    setUp(() async {
      await getIt.reset();
      authService = MockAuthService();
      googleSignIn = MockGoogleSignIn();
      when(() => authService.googleSignIn).thenReturn(googleSignIn);
      when(() => googleSignIn.signIn()).thenThrow(Exception('sign-in failed'));
      getIt.registerSingleton<AuthService>(authService);
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: const []),
      );
    });

    tearDown(getIt.reset);

    testWidgets('hands a Google failure to the service for reporting', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.tap(find.text('Sign in with Google'));
      await tester.pump();

      verify(() => authService.reportSignInFailure(any())).called(1);
    });
  });
}
