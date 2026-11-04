import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/common/widgets/brand_hero.dart';
import 'package:wishtogether/core/design_tokens.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/router.dart';

import '../../../core/logging/recording_sink.dart';

import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/phone_verification.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';

class MockAuthService extends Mock implements AuthService {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockUserRepository extends Mock implements UserRepository {}

const String phoneNumber = '4085551234';
const String verificationId = 'native-verification-id';

/// The two lines the login hero authors, so a wrappable paragraph cannot
/// satisfy the assertion.
const String firstTitleLine = 'Welcome to';
const String secondTitleLine = 'WishTogether';

/// The narrow phone the title has to survive.
const double viewportWidth = 320;

/// The top inset a notched phone reports.
const double statusBarInset = 47;

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

  group('LoginPage title', () {
    setUp(() async {
      await getIt.reset();
      getIt.registerSingleton<AuthService>(MockAuthService());
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: const []),
      );
    });

    tearDown(getIt.reset);

    testWidgets('scales the longer line down instead of breaking it', (
      tester,
    ) async {
      // Arrange: a 320 px phone at the largest system text scale. The title
      // was one paragraph on a screen this narrow, so it broke mid-word and
      // left a final "r" alone on a third line.
      tester.view.physicalSize = const Size(viewportWidth, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Act
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pump();

      // Assert: both authored lines survive as whole lines, and the one that
      // is wider than the block is scaled down rather than wrapped.
      expect(tester.takeException(), isNull);
      expect(find.text(firstTitleLine), findsOneWidget);
      expect(find.text('$firstTitleLine $secondTitleLine'), findsNothing);
      final longerLine = find.text(secondTitleLine);
      expect(longerLine, findsOneWidget);
      final scaled = find.ancestor(
        of: longerLine,
        matching: find.byType(FittedBox),
      );
      expect(scaled, findsOneWidget);
      expect(
        tester.getSize(longerLine).width,
        greaterThan(tester.getSize(scaled).width),
        reason: 'the line has to be wider than its box to need scaling',
      );
      expect(
        tester.getSize(scaled).width,
        // The hero pads its lines by spacingMd on each side.
        lessThanOrEqualTo(viewportWidth - 2 * BrandGeometry.spacingMd),
        reason: 'a scaled line never paints past the block',
      );
    });

    testWidgets('gives the form the room when the keyboard is up', (
      tester,
    ) async {
      // Arrange: a phone in landscape at 2.0 text scale with the keyboard
      // open. A pinned hero taller than the space left would overflow it, and
      // the status bar inset would land on the form if nothing took it over.
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      tester.view.padding = const FakeViewPadding(top: statusBarInset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Act
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pump();

      // Assert
      expect(tester.takeException(), isNull);
      expect(find.byType(BrandHero), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
        greaterThanOrEqualTo(statusBarInset),
        reason: 'the form has to start below the status bar',
      );
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

  group('LoginPage requests one code at a time', () {
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

    Future<void> pumpLogin(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: LoginPage.route,
        routes: [loginPageRoute()],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      await tester.enterText(find.byType(TextField), phoneNumber);
    }

    testWidgets('ignores a second tap before the platform reports', (
      tester,
    ) async {
      // Arrange: the request is in flight; no code has been sent yet.
      final inFlight = Completer<void>();
      when(() => authService.startPhoneVerification(any()))
          .thenAnswer((_) async {
            await inFlight.future;
            return const PhoneVerificationCodeSent(verificationId);
          });
      await pumpLogin(tester);

      // Act
      await tester.tap(find.text('Send Verification Code'));
      await tester.pump();
      await tester.tap(find.text('Send Verification Code'));
      await tester.pump();

      // Assert
      verify(() => authService.startPhoneVerification(any())).called(1);
    });

    testWidgets('re-enables Send after a failure', (tester) async {
      // Arrange
      when(() => authService.startPhoneVerification(any()))
          .thenThrow(FirebaseAuthException(code: 'too-many-requests'));
      await pumpLogin(tester);

      // Act
      await tester.tap(find.text('Send Verification Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send Verification Code'));
      await tester.pump();

      // Assert
      verify(() => authService.startPhoneVerification(any())).called(2);
    });

    testWidgets('tells the user when the platform never reports', (
      tester,
    ) async {
      // Arrange
      when(() => authService.startPhoneVerification(any()))
          .thenThrow(TimeoutException('the platform never reported'));
      await pumpLogin(tester);

      // Act
      await tester.tap(find.text('Send Verification Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      expect(find.text(LoginPage.timeoutMessage), findsOneWidget);
    });
  });

  group('LoginPage opens the verification page', () {
    late MockAuthService authService;
    late MockUserRepository userRepository;

    setUp(() async {
      await getIt.reset();
      authService = MockAuthService();
      userRepository = MockUserRepository();
      when(() => authService.currentUserId).thenReturn(null);
      when(() => authService.uidChanges)
          .thenAnswer((_) => const Stream<String?>.empty());
      getIt.registerSingleton<AuthService>(authService);
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: const []),
      );
    });

    tearDown(getIt.reset);

    /// Enters [phoneNumber] on login and sends a code, leaving the verification
    /// page on screen with its push transition finished.
    Future<void> openVerificationPage(WidgetTester tester) async {
      when(() => authService.startPhoneVerification(any())).thenAnswer(
        (_) async => const PhoneVerificationCodeSent(verificationId),
      );
      final router = createRouter(
        authService,
        userRepository: userRepository,
        initialLocation: LoginPage.route,
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      await tester.enterText(find.byType(TextField), phoneNumber);
      await tester.tap(find.text('Send Verification Code'));
      // Login's scroll indicator animates on a repeating controller, so
      // `pumpAndSettle` would never return; advance past the push transition.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('on top of login, with a back action', (tester) async {
      // Act
      await openVerificationPage(tester);

      // Assert
      expect(find.byType(VerificationPage), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('returns to login with the number still entered', (
      tester,
    ) async {
      // Arrange
      await openVerificationPage(tester);

      // Act
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The popped route is removed from the tree on the frame after its
      // transition finishes.
      await tester.pump();

      // Assert
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        phoneNumber,
      );
      // Leaving through the router must discard the pending sign-in, not only
      // dispose of the page: a browser-back is a different path from a rebuild.
      verify(() => authService.discardPendingPhoneSignIn()).called(1);
    });
  });
}
