import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';

import 'logging/recording_sink.dart';

import 'package:wishtogether/core/logging/session_context.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockFirebaseUser extends Mock implements firebase_auth.User {}

class MockProviderInfo extends Mock implements firebase_auth.UserInfo {}

const joinPath = '/join?group=123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService mockAuthService;
  late MockUserRepository mockUserRepository;

  setUp(() {
    mockAuthService = MockAuthService();
    mockUserRepository = MockUserRepository();
  });

  group('handleRedirect', () {
    group('user not logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUserId).thenReturn(null);
      });

      test('should not redirect when on the login page', () async {
        final result = await handleRedirect(
          LoginPage.route,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should not redirect when on the verify page', () async {
        final result = await handleRedirect(
          VerificationPage.route,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should redirect to login page from a protected page with redirect', () async {
        const initialRoute = HomePage.route; // This is '/'
        final result = await handleRedirect(
          initialRoute,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        final expectedRedirect =
            '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
        expect(result, expectedRedirect);
      });

      test('should redirect to login page preserving the join link as redirect_to', () async {
        final result = await handleRedirect(
          joinPath,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        final expectedRedirect =
            '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
        expect(result, expectedRedirect);
      });
    });

    group('user logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUserId).thenReturn('test-uid');
        when(() => mockAuthService.currentUserEmail).thenReturn(null);
        when(() => mockAuthService.currentUserPhoneNumber).thenReturn(null);
      });

      group('user has no display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
              phoneNumber: any(named: 'phoneNumber'),
            ),
          ).thenAnswer((_) async => User(id: 'test-uid'));
        });

        test('should not redirect when on the profile page', () async {
          final result = await handleRedirect(
            ProfilePage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, isNull);
        });

        test('should redirect to profile page from a protected page', () async {
          const initialRoute = HomePage.route; // This is '/'
          final result = await handleRedirect(
            initialRoute,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to the profile page when signing in from the login page', () async {
          // A brand-new account signs in on /login; home has no user document
          // to render, so it must reach onboarding instead.
          final result = await handleRedirect(
            LoginPage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, ProfilePage.route);
        });

        test('should send a new account to the profile page, preserving redirect_to', () async {
          final loginUriWithRedirect =
              '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          final result = await handleRedirect(
            loginUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to profile page preserving the join link as redirect_to', () async {
          final result = await handleRedirect(
            joinPath,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to profile page preserving redirect_to from verify page', () async {
          final verifyUriWithRedirect =
              '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          final result = await handleRedirect(
            verifyUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          expect(result, expectedRedirect);
        });
      });

      group('user has a display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
              phoneNumber: any(named: 'phoneNumber'),
            ),
          ).thenAnswer(
            (_) async => User(
              id: 'test-uid',
              email: 'test@test.com',
              displayName: 'Test User',
            ),
          );
        });

        test(
          'should redirect to home page when on login page without redirect',
          () async {
            final result = await handleRedirect(
              LoginPage.route,
              mockAuthService,
              userRepo: mockUserRepository,
            );
            expect(result, HomePage.route);
          },
        );

        test('should redirect to join link after login', () async {
          final loginUriWithRedirect =
              '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          final result = await handleRedirect(
            loginUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, joinPath);
        });

        test('should redirect to join link after verification', () async {
          final verifyUriWithRedirect =
              '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          final result = await handleRedirect(
            verifyUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, joinPath);
        });

        test(
          'should not redirect from any other page (including join link)',
          () async {
            // From home
            var result = await handleRedirect(
              HomePage.route,
              mockAuthService,
              userRepo: mockUserRepository,
            );
            expect(result, isNull);

            // From join link
            result = await handleRedirect(
              '/join?group=123',
              mockAuthService,
              userRepo: mockUserRepository,
            );
            expect(result, isNull);
          },
        );
      });
    });
  });

  group('handleRedirect repository resolution', () {
    test('uses the registered UserRepository when none is passed', () async {
      when(() => mockAuthService.currentUserId).thenReturn('test-uid');
      when(() => mockAuthService.currentUserEmail).thenReturn(null);
      when(() => mockAuthService.currentUserPhoneNumber).thenReturn(null);
      when(
        () => mockUserRepository.getOrCreateUser(
          any(),
          email: any(named: 'email'),
          phoneNumber: any(named: 'phoneNumber'),
        ),
      ).thenAnswer((_) async => User(id: 'test-uid', displayName: 'Sasha'));
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      addTearDown(getIt.reset);

      final result = await handleRedirect(HomePage.route, mockAuthService);

      expect(result, isNull);
      verify(
        () => mockUserRepository.getOrCreateUser(
          'test-uid',
          email: null,
          phoneNumber: null,
        ),
      ).called(1);
    });
  });

  group('resolveUserRepository', () {
    test('uses the injected repository', () {
      final injected = MockUserRepository();

      expect(resolveUserRepository(injected), same(injected));
    });

    test('falls back to the registered repository', () {
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      addTearDown(getIt.reset);

      expect(resolveUserRepository(), same(mockUserRepository));
    });
  });

  group('deep-link startup', () {
    test('createRouter starts at the supplied initial location', () {
      when(() => mockAuthService.authStateChanges)
          .thenAnswer((_) => const Stream.empty());

      const initialLocation = '/join?group=123';
      final router = createRouter(
        mockAuthService,
        userRepository: mockUserRepository,
        initialLocation: initialLocation,
      );
      addTearDown(router.dispose);

      expect(
        router.routeInformationProvider.value.uri.toString(),
        initialLocation,
      );
    });

    test('forwards a full URL as an opaque location', () async {
      when(() => mockAuthService.currentUserId).thenReturn(null);

      const hashLogin = 'https://wishtogether.gift/#/login';
      final result = await handleRedirect(
        hashLogin,
        mockAuthService,
        userRepo: mockUserRepository,
      );

      expect(
        result,
        '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(hashLogin)}',
      );
    });
  });

  group('route diagnostics', () {
    late RecordingSink sink;

    setUp(() async {
      await getIt.reset();
      sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      when(() => mockAuthService.authStateChanges)
          .thenAnswer((_) => const Stream.empty());
      when(() => mockAuthService.currentUserId).thenReturn('user-1');
      when(
        () => mockUserRepository.getOrCreateUser(
          any(),
          email: any(named: 'email'),
          phoneNumber: any(named: 'phoneNumber'),
        ),
      ).thenAnswer((_) async => User(id: 'user-1', displayName: 'Grace'));
    });

    tearDown(getIt.reset);

    List<String> patterns() =>
        sink.eventsOf<RouteChangedEvent>().map((event) => event.route).toList();

    GoRouter buildRouter({String? initialLocation}) {
      final router = createRouter(
        mockAuthService,
        userRepository: mockUserRepository,
        initialLocation: initialLocation,
      );
      addTearDown(router.dispose);
      return router;
    }

    test('records a go() location as a route pattern', () async {
      final router = buildRouter();

      router.go('/wishlist/abc123?tab=1');
      await pumpEventQueue();

      expect(patterns(), contains('/wishlist/:id'));
    });

    test('records one entry for two ids on the same route', () async {
      final router = buildRouter();

      router.go('/wishlist/first');
      await pumpEventQueue();
      router.go('/wishlist/second');
      await pumpEventQueue();

      expect(
        patterns().where((pattern) => pattern == '/wishlist/:id'),
        hasLength(1),
      );
    });

    test('does not record the initial location twice', () async {
      buildRouter(initialLocation: '/join?group=123');

      await pumpEventQueue();

      expect(patterns(), isEmpty);
    });

    test('never records a document id', () async {
      final router = buildRouter();

      router.go('/wishlist/abc123');
      await pumpEventQueue();

      expect(patterns().join(' '), isNot(contains('abc123')));
    });
  });

  group('auth diagnostics', () {
    late RecordingSink sink;
    late StreamController<firebase_auth.User?> authChanges;

    setUp(() async {
      await getIt.reset();
      sink = RecordingSink();
      authChanges = StreamController<firebase_auth.User?>();
      addTearDown(authChanges.close);
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      when(() => mockAuthService.authStateChanges)
          .thenAnswer((_) => authChanges.stream);
    });

    tearDown(getIt.reset);

    List<AuthStateEvent> authEvents() =>
        sink.eventsOf<AuthStateEvent>().toList();

    GoRouter buildRouter() {
      final router = createRouter(
        mockAuthService,
        userRepository: mockUserRepository,
      );
      addTearDown(router.dispose);
      return router;
    }

    test(
      'reports the signed-in provider and stores only the derived ref',
      () async {
        const uid = 'firebase-uid-1';
        final user = MockFirebaseUser();
        final phone = MockProviderInfo();
        when(() => user.uid).thenReturn(uid);
        when(() => user.providerData)
            .thenReturn(<firebase_auth.UserInfo>[phone]);
        when(() => phone.providerId).thenReturn('phone');
        buildRouter();

        authChanges.add(user);
        await pumpEventQueue();

        expect(authEvents().single.outcome, AuthOutcome.phone);
        final record = sink.records.last;
        expect(record.session.userRef, userRefForUid(uid));
        expect(
          record.toMap().values.join(' '),
          isNot(contains(uid)),
          reason: 'a raw uid must never reach a record',
        );
      },
    );

    test('reports a sign-out transition', () async {
      buildRouter();

      authChanges.add(null);
      await pumpEventQueue();

      expect(authEvents().single.outcome, AuthOutcome.signedOut);
      expect(sink.records.last.session.userRef, isNull);
    });
  });
}
