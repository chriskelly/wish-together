import 'dart:async';

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

/// Whether the Verify button can currently submit.
bool verifyEnabled(WidgetTester tester) =>
    tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Verify'))
        .onPressed !=
    null;

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
      await tester.pump();

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      expect(find.text(phoneAuthErrorMessage(failure)), findsOneWidget);
      expect(find.text(testSession.supportCode), findsOneWidget);
      expect(
        verifyEnabled(tester),
        isTrue,
        reason: 'the retry path stays open',
      );
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
      await tester.pump();

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      expect(find.text(VerificationPage.expiredSignInMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('VerificationPage code validation', () {
    testWidgets('keeps Verify disabled until the code is complete', (
      tester,
    ) async {
      // Arrange
      await tester.pumpWidget(verificationPage());
      expect(verifyEnabled(tester), isFalse);

      // Act: one digit short.
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();

      // Assert
      expect(verifyEnabled(tester), isFalse);

      // Act: the sixth digit completes it.
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      // Assert
      expect(verifyEnabled(tester), isTrue);
    });

    testWidgets('an empty tap cannot confirm a code', (tester) async {
      // Arrange
      await tester.pumpWidget(verificationPage());

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pump();

      // Assert
      verifyNever(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      );
    });

    testWidgets('ignores a second tap while a confirmation is in flight', (
      tester,
    ) async {
      // Arrange: the first confirmation has not come back yet.
      final inFlight = Completer<UserCredential>();
      final failure = FirebaseAuthException(code: 'network-request-failed');
      when(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).thenAnswer((_) => inFlight.future);
      await tester.pumpWidget(verificationPage());
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      // Act: two taps before the first frame, so the handler guard is what
      // stops the second request rather than the disabled paint. The first
      // confirmation then fails, which also lets the page settle.
      await tester.tap(find.text('Verify'));
      await tester.tap(find.text('Verify'));
      await tester.pump();
      inFlight.completeError(failure);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      verify(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).called(1);
    });

    testWidgets('submits the code without surrounding whitespace', (
      tester,
    ) async {
      // Arrange
      when(
        () => authService.confirmPhoneCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'invalid-verification-code'));
      await tester.pumpWidget(verificationPage());
      await tester.enterText(find.byType(TextField), ' 123456 ');
      await tester.pump();

      // Act
      await tester.tap(find.text('Verify'));
      await tester.pump();

      // Assert
      verify(
        () => authService.confirmPhoneCode(
          verificationId: verificationId,
          smsCode: '123456',
        ),
      ).called(1);
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
      await tester.pump();

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
