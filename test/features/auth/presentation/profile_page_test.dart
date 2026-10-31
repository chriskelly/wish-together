import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/common/widgets/support_code_tile.dart';
import 'package:wishtogether/core/logging/app_log.dart';

import '../../../core/logging/recording_sink.dart';

import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/delete_account_use_case.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';

/// Copy the profile page shows when it cannot read the profile.
const loadFailedHeadline = 'Could not load your profile.';
const loadFailedGuidance = 'Check your connection and try again.';
const retryLabel = 'Try again';

class MockAuthService extends Mock implements AuthService {}

class MockLoadUserProfileUseCase extends Mock
    implements LoadUserProfileUseCase {}

void main() {
  group('shouldShowProfileBackButton', () {
    test('offers the way out to a loaded existing user', () {
      expect(
        shouldShowProfileBackButton(
          loadState: ProfileLoadState.loaded,
          isNewUser: false,
        ),
        isTrue,
      );
    });

    test('keeps a new user in onboarding', () {
      expect(
        shouldShowProfileBackButton(
          loadState: ProfileLoadState.loaded,
          isNewUser: true,
        ),
        isFalse,
      );
    });

    test('waits for the profile to load', () {
      expect(
        shouldShowProfileBackButton(
          loadState: ProfileLoadState.loading,
          isNewUser: false,
        ),
        isFalse,
      );
    });

    test('offers nothing while a new user is still loading', () {
      expect(
        shouldShowProfileBackButton(
          loadState: ProfileLoadState.loading,
          isNewUser: true,
        ),
        isFalse,
      );
    });

    test('offers nothing after a failed load, even for an existing user', () {
      expect(
        shouldShowProfileBackButton(
          loadState: ProfileLoadState.failed,
          isNewUser: false,
        ),
        isFalse,
      );
    });
  });

  group('profilePageTitle', () {
    test('titles a loaded new user with the welcome task', () {
      expect(
        profilePageTitle(loadState: ProfileLoadState.loaded, isNewUser: true),
        'Create Your Profile',
      );
    });

    test('titles a loaded existing user as an edit', () {
      expect(
        profilePageTitle(loadState: ProfileLoadState.loaded, isNewUser: false),
        'Edit Profile',
      );
    });

    test('stays neutral while the profile is loading', () {
      expect(
        profilePageTitle(loadState: ProfileLoadState.loading, isNewUser: true),
        'Profile',
      );
    });

    test('stays neutral after a failed load, where the user is unknown', () {
      expect(
        profilePageTitle(loadState: ProfileLoadState.failed, isNewUser: true),
        'Profile',
      );
    });
  });

  group('ProfilePage', () {
    late MockLoadUserProfileUseCase loadUserProfile;
    late MockAuthService authService;

    setUp(() {
      getIt.reset();
      loadUserProfile = MockLoadUserProfileUseCase();
      authService = MockAuthService();
      // The production session offers deletion; the page only hides the danger
      // zone for a session that cannot delete an account.
      when(() => authService.supportsAccountDeletion).thenReturn(true);
      getIt.registerSingleton<LoadUserProfileUseCase>(loadUserProfile);
      // `_ProfilePageState` resolves the save use case when it is created and
      // the delete section resolves its two services when the form is built,
      // so all three must be registered even though these tests never save or
      // delete.
      getIt.registerSingleton<SaveUserProfileUseCase>(SaveUserProfileUseCase());
      getIt.registerSingleton<AuthService>(authService);
      getIt.registerSingleton<AuthSession>(authService);
      getIt.registerSingleton<DeleteAccountUseCase>(DeleteAccountUseCase());
    });

    tearDown(getIt.reset);

    Future<void> pumpProfilePage(WidgetTester tester) =>
        tester.pumpWidget(const MaterialApp(home: ProfilePage()));

    /// Fails every read the way an offline or permission-denied read does.
    ///
    /// The error is raised inside an async body so it arrives after
    /// `initState`, exactly as production's async use case behaves.
    void stubLoadFailure() {
      when(() => loadUserProfile.execute())
          .thenAnswer((_) async => throw Exception('offline'));
    }

    testWidgets('shows an error instead of an endless spinner', (tester) async {
      // Arrange
      stubLoadFailure();

      // Act
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(loadFailedHeadline), findsOneWidget);
      expect(find.text(loadFailedGuidance), findsOneWidget);
      expect(find.text(retryLabel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('offers no exit from the error state except retry', (
      tester,
    ) async {
      // Arrange
      stubLoadFailure();
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(loadFailedHeadline), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Save and Continue'), findsNothing);
      expect(find.text('Delete account'), findsNothing);
    });

    testWidgets('treats a missing profile as a failed read', (tester) async {
      // Arrange
      when(() => loadUserProfile.execute()).thenAnswer((_) async => null);

      // Act
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(loadFailedHeadline), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders the profile after a successful retry', (tester) async {
      // Arrange
      const displayName = 'Grace Hopper';
      final user = User(id: 'user-1', displayName: displayName);
      var reads = 0;
      when(() => loadUserProfile.execute()).thenAnswer((_) async {
        reads++;
        if (reads == 1) {
          throw Exception('offline');
        }
        return user;
      });
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(retryLabel));
      await tester.pumpAndSettle();

      // Assert
      expect(reads, 2);
      expect(find.text(displayName), findsOneWidget);
      expect(find.text('Save and Continue'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Delete account'),
        findsOneWidget,
      );
      expect(find.text(loadFailedHeadline), findsNothing);
    });

    testWidgets(
      'hides account deletion when the session cannot delete accounts',
      (tester) async {
        // Arrange
        when(() => authService.supportsAccountDeletion).thenReturn(false);
        when(() => loadUserProfile.execute()).thenAnswer(
          (_) async => User(id: 'user-1', displayName: 'Grace Hopper'),
        );

        // Act
        await pumpProfilePage(tester);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Save and Continue'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Delete account'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'keeps a nameless user in onboarding after a successful retry',
      (tester) async {
        // Arrange
        final user = User(id: 'user-2');
        var reads = 0;
        when(() => loadUserProfile.execute()).thenAnswer((_) async {
          reads++;
          if (reads == 1) {
            throw Exception('offline');
          }
          return user;
        });
        await pumpProfilePage(tester);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(retryLabel));
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.text('Welcome! Please enter your name to continue.'),
          findsOneWidget,
        );
        expect(find.byType(BackButton), findsNothing);
      },
    );

    testWidgets('keeps the retry available when the retry also fails', (
      tester,
    ) async {
      // Arrange
      stubLoadFailure();
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(retryLabel));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(loadFailedHeadline), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      verify(() => loadUserProfile.execute()).called(2);
    });

    testWidgets('shows the spinner while the retry is in flight', (
      tester,
    ) async {
      // Arrange
      const displayName = 'Ada Lovelace';
      final retry = Completer<User?>();
      var reads = 0;
      when(() => loadUserProfile.execute()).thenAnswer((_) {
        reads++;
        if (reads == 1) {
          return Future<User?>.error(Exception('offline'));
        }
        return retry.future;
      });
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(retryLabel));
      await tester.pump();

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(loadFailedHeadline), findsNothing);

      retry.complete(User(id: 'user-3', displayName: displayName));
      await tester.pumpAndSettle();
      expect(find.text(displayName), findsOneWidget);
    });

    testWidgets('starts one read per retry, even on a double tap', (
      tester,
    ) async {
      // Arrange
      const displayName = 'Ada Lovelace';
      final retry = Completer<User?>();
      var reads = 0;
      when(() => loadUserProfile.execute()).thenAnswer((_) {
        reads++;
        if (reads == 1) {
          return Future<User?>.error(Exception('offline'));
        }
        return retry.future;
      });
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Act: both taps land before the frame that swaps the panel for the
      // spinner, so the second one hits a still-enabled Retry.
      await tester.tap(find.text(retryLabel));
      await tester.tap(find.text(retryLabel));
      await tester.pump();

      // Assert
      expect(reads, 2);

      retry.complete(User(id: 'user-4', displayName: displayName));
      await tester.pumpAndSettle();
      expect(find.text(displayName), findsOneWidget);
    });

    testWidgets('leaves a disposed page alone when a read fails later', (
      tester,
    ) async {
      // Arrange
      final retry = Completer<User?>();
      var reads = 0;
      when(() => loadUserProfile.execute()).thenAnswer((_) {
        reads++;
        if (reads == 1) {
          return Future<User?>.error(Exception('offline'));
        }
        return retry.future;
      });
      await pumpProfilePage(tester);
      await tester.pumpAndSettle();

      // Act: a session revoked mid-retry would take the page with it.
      await tester.tap(find.text(retryLabel));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      retry.completeError(Exception('signed out'));
      await tester.pump();

      // Assert
      expect(tester.takeException(), isNull);
    });
  });

  group('profileExitTarget', () {
    test('returns the destination the user was headed for', () {
      const wishlistId = 'abc';
      final destination = '/wishlist/$wishlistId';

      expect(profileExitTarget(destination), destination);
    });

    test('keeps an invitation path intact', () {
      const groupId = '123';
      final invitation = '${JoinGroupPage.route}?group=$groupId';

      expect(profileExitTarget(invitation), invitation);
    });

    test('falls back to home without a destination', () {
      expect(profileExitTarget(null), HomePage.route);
    });

    test('falls back to home for a blank destination', () {
      expect(profileExitTarget(''), HomePage.route);
    });

    test('falls back to home for a whitespace-only destination', () {
      expect(profileExitTarget('   '), HomePage.route);
    });

    test('falls back to home when the destination is the profile page', () {
      expect(profileExitTarget(ProfilePage.route), HomePage.route);
    });

    test('falls back to home for the profile page with a trailing slash', () {
      expect(profileExitTarget('${ProfilePage.route}/'), HomePage.route);
    });

    test('falls back to home for the profile page with a query string', () {
      expect(
        profileExitTarget('${ProfilePage.route}?redirect_to=%2F'),
        HomePage.route,
      );
    });
  });

  group('ProfilePage support code', () {
    late MockLoadUserProfileUseCase loadUserProfile;

    setUp(() async {
      await getIt.reset();
      loadUserProfile = MockLoadUserProfileUseCase();
      getIt.registerSingleton<LoadUserProfileUseCase>(loadUserProfile);
      getIt.registerSingleton<SaveUserProfileUseCase>(SaveUserProfileUseCase());
      final authService = MockAuthService();
      when(() => authService.supportsAccountDeletion).thenReturn(true);
      getIt.registerSingleton<AuthService>(authService);
      getIt.registerSingleton<AuthSession>(authService);
      getIt.registerSingleton<DeleteAccountUseCase>(DeleteAccountUseCase());
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: const []),
      );
    });

    tearDown(getIt.reset);

    testWidgets('shows the support code once the profile has loaded', (
      tester,
    ) async {
      // Arrange
      when(() => loadUserProfile.execute()).thenAnswer(
        (_) async => User(id: 'user-1', displayName: 'Grace Hopper'),
      );

      // Act
      await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(testSession.supportCode), findsOneWidget);
      expect(find.text(SupportCodeTile.explanation), findsOneWidget);
    });

    testWidgets('keeps the support code off the failed-load screen', (
      tester,
    ) async {
      // Arrange
      when(() => loadUserProfile.execute())
          .thenAnswer((_) async => throw Exception('offline'));

      // Act
      await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(testSession.supportCode), findsNothing);
      expect(find.text(loadFailedHeadline), findsOneWidget);
    });
  });
}
