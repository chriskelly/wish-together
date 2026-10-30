import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/phone_auth_error.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';

import '../../../core/logging/recording_sink.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserCredential extends Mock implements UserCredential {}

const String verificationId = 'web-verification-id';

void main() {
  late MockAuthService authService;

  setUp(() async {
    await getIt.reset();
    authService = MockAuthService();
    getIt.registerSingleton<AuthService>(authService);
    getIt.registerSingleton<AppLog>(
      AppLog(session: testSession, sinks: const []),
    );
  });

  tearDown(getIt.reset);

  Widget verificationPage() =>
      MaterialApp(home: VerificationPage(verificationId: verificationId));

  group('VerificationPage support code', () {
    testWidgets('shows the code the user reads out to support', (tester) async {
      // Arrange
      await tester.pumpWidget(verificationPage());

      // Assert
      expect(find.text(testSession.supportCode), findsOneWidget);
    });

    testWidgets('keeps the code visible after a failed confirmation', (
      tester,
    ) async {
      // Arrange
      final failure = FirebaseAuthException(code: 'invalid-verification-code');
      when(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).thenThrow(failure);
      await tester.pumpWidget(verificationPage());
      await tester.enterText(find.byType(TextField), '000000');

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      expect(find.text(phoneAuthErrorMessage(failure)), findsOneWidget);
      expect(find.text(testSession.supportCode), findsOneWidget);
    });
  });

  group('VerificationPage expired sign-in', () {
    testWidgets('tells the user to request a new code', (tester) async {
      // Arrange: the page outlived the web sign-in it was opened for.
      when(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).thenThrow(StateError('No web phone sign-in in progress.'));
      await tester.pumpWidget(verificationPage());
      await tester.enterText(find.byType(TextField), '000000');

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      expect(find.text(VerificationPage.expiredSignInMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('VerificationPage leaving the page', () {
    testWidgets('discards the pending phone sign-in', (tester) async {
      // Arrange
      await tester.pumpWidget(verificationPage());

      // Act
      await tester.pumpWidget(const SizedBox.shrink());

      // Assert
      verify(() => authService.discardPendingPhoneSignIn()).called(1);
    });
  });

  group('VerificationPage navigation', () {
    testWidgets('a confirmed code lands on the redirect target', (
      tester,
    ) async {
      // Arrange: a real router, so the destination and the stack are real.
      when(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).thenAnswer((_) async => MockUserCredential());
      final router = GoRouter(
        initialLocation: '/start',
        routes: <RouteBase>[
          GoRoute(
            path: '/start',
            builder: (_, _) => const Scaffold(body: Text('start')),
          ),
          verificationPageRoute(),
          GoRoute(
            path: '/dest',
            builder: (_, _) => const Scaffold(body: Text('destination')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.push('/verify?redirect_to=%2Fdest', extra: verificationId);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      // Assert: the destination replaced the stack, so back cannot return to
      // a code page that has already been used.
      expect(find.text('destination'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });
  });
}
