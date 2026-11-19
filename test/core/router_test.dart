import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';

import 'logging/recording_sink.dart';

import 'package:wishtogether/core/logging/session_context.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/route_state.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

import '../support/router_state.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockUserRepository extends Mock implements UserRepository {}

const joinPath = '/join?group=123';

/// The widget a route page builds, unwrapping the page's builder context.
Widget pageChild(GoRoute route, BuildContext context, GoRouterState state) {
  final page = route.pageBuilder!(context, state) as MaterialPage<void>;
  final child = page.child;
  return child is Builder ? child.builder(context) : child;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthSession mockSession;
  late MockUserRepository mockUserRepository;

  setUp(() {
    mockSession = MockAuthSession();
    mockUserRepository = MockUserRepository();
  });

  group('handleRedirect', () {
    group('user not logged in', () {
      setUp(() {
        when(() => mockSession.currentUserId).thenReturn(null);
      });

      test('should not redirect when on the login page', () async {
        final result = await handleRedirect(
          LoginPage.route,
          mockSession,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should not redirect when on the verify page', () async {
        final result = await handleRedirect(
          VerificationPage.route,
          mockSession,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should redirect to login page from a protected page with redirect', () async {
        const initialRoute = HomePage.route; // This is '/'
        final result = await handleRedirect(
          initialRoute,
          mockSession,
          userRepo: mockUserRepository,
        );
        final expectedRedirect =
            '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
        expect(result, expectedRedirect);
      });

      test('should redirect to login page preserving the join link as redirect_to', () async {
        final result = await handleRedirect(
          joinPath,
          mockSession,
          userRepo: mockUserRepository,
        );
        final expectedRedirect =
            '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
        expect(result, expectedRedirect);
      });
    });

    group('user logged in', () {
      setUp(() {
        when(() => mockSession.currentUserId).thenReturn('test-uid');
        when(() => mockSession.currentUserEmail).thenReturn(null);
        when(() => mockSession.currentUserPhoneNumber).thenReturn(null);
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
            mockSession,
            userRepo: mockUserRepository,
          );
          expect(result, isNull);
        });

        test('should redirect to profile page from a protected page', () async {
          const initialRoute = HomePage.route; // This is '/'
          final result = await handleRedirect(
            initialRoute,
            mockSession,
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
            mockSession,
            userRepo: mockUserRepository,
          );
          expect(result, ProfilePage.route);
        });

        test('should send a new account to the profile page, preserving redirect_to', () async {
          final loginUriWithRedirect =
              '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          final result = await handleRedirect(
            loginUriWithRedirect,
            mockSession,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to profile page preserving the join link as redirect_to', () async {
          final result = await handleRedirect(
            joinPath,
            mockSession,
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
            mockSession,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          expect(result, expectedRedirect);
        });
      });

      group('user has only a whitespace display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
              phoneNumber: any(named: 'phoneNumber'),
            ),
          ).thenAnswer((_) async => User(id: 'test-uid', displayName: '   '));
        });

        test('should redirect to profile page from a protected page', () async {
          const initialRoute = HomePage.route;

          final result = await handleRedirect(
            initialRoute,
            mockSession,
            userRepo: mockUserRepository,
          );

          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
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
              mockSession,
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
            mockSession,
            userRepo: mockUserRepository,
          );
          expect(result, joinPath);
        });

        test('should redirect to join link after verification', () async {
          final verifyUriWithRedirect =
              '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(joinPath)}';
          final result = await handleRedirect(
            verifyUriWithRedirect,
            mockSession,
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
              mockSession,
              userRepo: mockUserRepository,
            );
            expect(result, isNull);

            // From join link
            result = await handleRedirect(
              '/join?group=123',
              mockSession,
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
      when(() => mockSession.currentUserId).thenReturn('test-uid');
      when(() => mockSession.currentUserEmail).thenReturn(null);
      when(() => mockSession.currentUserPhoneNumber).thenReturn(null);
      when(
        () => mockUserRepository.getOrCreateUser(
          any(),
          email: any(named: 'email'),
          phoneNumber: any(named: 'phoneNumber'),
        ),
      ).thenAnswer((_) async => User(id: 'test-uid', displayName: 'Sasha'));
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      addTearDown(getIt.reset);

      final result = await handleRedirect(HomePage.route, mockSession);

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
      when(() => mockSession.uidChanges)
          .thenAnswer((_) => const Stream<String?>.empty());

      const initialLocation = '/join?group=123';
      final router = createRouter(
        mockSession,
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
      when(() => mockSession.currentUserId).thenReturn(null);

      const hashLogin = 'https://wishtogether.gift/#/login';
      final result = await handleRedirect(
        hashLogin,
        mockSession,
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
      when(() => mockSession.uidChanges)
          .thenAnswer((_) => const Stream<String?>.empty());
      when(() => mockSession.currentUserId).thenReturn('user-1');
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
        mockSession,
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
    late StreamController<String?> authChanges;

    setUp(() async {
      await getIt.reset();
      sink = RecordingSink();
      authChanges = StreamController<String?>();
      addTearDown(authChanges.close);
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      when(() => mockSession.uidChanges).thenAnswer((_) => authChanges.stream);
      when(() => mockSession.providerIds).thenReturn(const <String>[]);
    });

    tearDown(getIt.reset);

    List<AuthStateEvent> authEvents() =>
        sink.eventsOf<AuthStateEvent>().toList();

    GoRouter buildRouter() {
      final router = createRouter(
        mockSession,
        userRepository: mockUserRepository,
      );
      addTearDown(router.dispose);
      return router;
    }

    test(
      'reports the signed-in provider and stores only the derived ref',
      () async {
        const uid = 'firebase-uid-1';
        when(() => mockSession.providerIds).thenReturn(const <String>['phone']);
        buildRouter();

        authChanges.add(uid);
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

    test(
      'reports each transition with the provider of that transition',
      () async {
        buildRouter();
        when(() => mockSession.providerIds).thenReturn(const <String>['phone']);

        authChanges.add('uid-phone');
        await pumpEventQueue();

        when(() => mockSession.providerIds)
            .thenReturn(const <String>['apple.com']);
        authChanges.add('uid-apple');
        await pumpEventQueue();

        expect(
          authEvents().map((event) => event.outcome).toList(),
          <AuthOutcome>[AuthOutcome.phone, AuthOutcome.apple],
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

  group('onExit pop', () {
    testWidgets('an async redirect does not resurrect a popped route', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/detail',
        redirect: (context, state) async {
          await Future<void>.delayed(Duration.zero);
          return null;
        },
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home')),
            routes: [
              GoRoute(
                path: 'detail',
                onExit: (context, state) => true,
                builder: (context, state) =>
                    const Scaffold(body: Text('detail')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('item form routes', () {
    testWidgets(
      'a create deep link without route args falls back to the list',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/wishlist/w1',
          routes: [
            GoRoute(
              path: '/wishlist/:id',
              builder: (context, state) => const Scaffold(body: Text('list')),
              routes: [itemFormPageCreateRoute()],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        router.go('/wishlist/w1/add-item');
        await tester.pumpAndSettle();

        expect(find.text('list'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a deep link without route args falls back to the list', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/wishlist/w1',
        routes: [
          GoRoute(
            path: '/wishlist/:id',
            builder: (context, state) => const Scaffold(body: Text('list')),
            routes: [itemFormPageEditRoute()],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/wishlist/w1/item/i1/edit');
      await tester.pumpAndSettle();

      expect(find.text('list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('route extras', () {
    GoRouter newRouter() {
      final router = stateFixtureRouter();
      addTearDown(router.dispose);
      return router;
    }

    testWidgets('a create redirect without an id goes home', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();

      final result = await itemFormPageCreateRoute().redirect!(
        context,
        stateFixture(router, location: '/wishlist/add-item'),
      );

      expect(result, HomePage.route);
    });

    testWidgets('a create redirect with a blank id goes home', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();

      final result = await itemFormPageCreateRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/add-item',
          pathParameters: const <String, String>{'id': '  '},
        ),
      );

      expect(result, HomePage.route);
    });

    testWidgets('a create redirect without args returns to the list', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';

      final result = await itemFormPageCreateRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/add-item',
          pathParameters: const <String, String>{'id': wishlistId},
        ),
      );

      expect(result, '/wishlist/$wishlistId');
    });

    testWidgets('a create redirect with args lets the form build', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';

      final result = await itemFormPageCreateRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/add-item',
          pathParameters: const <String, String>{'id': wishlistId},
          extra: CreateItemRouteArgs(),
        ),
      );

      expect(result, isNull);
    });

    testWidgets('a create builder without args is unavailable', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();

      final widget = pageChild(
        itemFormPageCreateRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/w1/add-item',
          pathParameters: const <String, String>{'id': 'w1'},
        ),
      );

      expect(widget, isA<RouteUnavailablePage>());
    });

    testWidgets('a create builder without an id is unavailable', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();

      final widget = pageChild(
        itemFormPageCreateRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/add-item',
          extra: CreateItemRouteArgs(),
        ),
      );

      expect(widget, isA<RouteUnavailablePage>());
    });

    testWidgets('a create builder with an id and args builds the form', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';
      final args = CreateItemRouteArgs();

      final widget = pageChild(
        itemFormPageCreateRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/add-item',
          pathParameters: const <String, String>{'id': wishlistId},
          extra: args,
        ),
      ) as ItemFormPage;

      expect(widget.wishlistId, wishlistId);
      expect(widget.leaveGuard, same(args.leaveGuard));
    });

    testWidgets('an item edit without args is unavailable', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';

      final widget = pageChild(
        itemFormPageEditRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/item/i1/edit',
          pathParameters: const <String, String>{
            'id': wishlistId,
            'itemId': 'i1',
          },
        ),
      );

      expect(widget, isA<RouteUnavailablePage>());
    });

    testWidgets('an item edit without args returns to the list', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';

      final redirected = await itemFormPageEditRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/item/i1/edit',
          pathParameters: const <String, String>{
            'id': wishlistId,
            'itemId': 'i1',
          },
        ),
      );

      expect(redirected, '/wishlist/$wishlistId');
    });

    testWidgets('an item edit with args is allowed', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';
      final args = EditItemRouteArgs(Item(name: 'Lamp'));

      final allowed = await itemFormPageEditRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/item/i1/edit',
          pathParameters: const <String, String>{
            'id': wishlistId,
            'itemId': 'i1',
          },
          extra: args,
        ),
      );

      expect(allowed, isNull);
    });

    testWidgets('an item edit with args builds the form', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';
      final args = EditItemRouteArgs(Item(name: 'Lamp'));

      final widget = pageChild(
        itemFormPageEditRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/item/i1/edit',
          pathParameters: const <String, String>{
            'id': wishlistId,
            'itemId': 'i1',
          },
          extra: args,
        ),
      ) as ItemFormPage;

      expect(widget.item, same(args.item));
      expect(widget.leaveGuard, same(args.leaveGuard));
    });

    testWidgets('a wishlist edit without its extra returns to the list', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';

      final redirected = await wishlistFormPageEditRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/edit',
          pathParameters: const <String, String>{'id': wishlistId},
        ),
      );

      expect(redirected, '/wishlist/$wishlistId');
    });

    testWidgets('a wishlist edit with its extra is allowed', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';
      final wishlist = Wishlist(
        id: wishlistId,
        name: 'Birthday',
        ownerId: 'owner',
      );

      final allowed = await wishlistFormPageEditRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/edit',
          pathParameters: const <String, String>{'id': wishlistId},
          extra: wishlist,
        ),
      );

      expect(allowed, isNull);
    });

    testWidgets('a wishlist edit without its extra is unavailable', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';

      final widget = pageChild(
        wishlistFormPageEditRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/edit',
          pathParameters: const <String, String>{'id': wishlistId},
        ),
      );

      expect(widget, isA<RouteUnavailablePage>());
    });

    testWidgets('a wishlist edit with its extra builds the form', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const wishlistId = 'w1';
      final wishlist = Wishlist(
        id: wishlistId,
        name: 'Birthday',
        ownerId: 'owner',
      );

      final widget = pageChild(
        wishlistFormPageEditRoute(),
        context,
        stateFixture(
          router,
          location: '/wishlist/$wishlistId/edit',
          pathParameters: const <String, String>{'id': wishlistId},
          extra: wishlist,
        ),
      );

      expect(widget, isA<WishlistFormPage>());
    });

    testWidgets('a group edit without its extra returns to the group', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const groupId = 'g1';

      final redirected = await groupFormPageEditRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/group/$groupId/edit',
          pathParameters: const <String, String>{'id': groupId},
        ),
      );

      expect(redirected, '/group/$groupId');
    });

    testWidgets('a group edit with its extra is allowed', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const groupId = 'g1';
      final group = Group(
        id: groupId,
        name: 'Family',
        ownerId: 'owner',
        members: const <String>['owner'],
      );

      final allowed = await groupFormPageEditRoute().redirect!(
        context,
        stateFixture(
          router,
          location: '/group/$groupId/edit',
          pathParameters: const <String, String>{'id': groupId},
          extra: group,
        ),
      );

      expect(allowed, isNull);
    });

    testWidgets('a group edit without its extra is unavailable', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const groupId = 'g1';

      final widget = pageChild(
        groupFormPageEditRoute(),
        context,
        stateFixture(
          router,
          location: '/group/$groupId/edit',
          pathParameters: const <String, String>{'id': groupId},
        ),
      );

      expect(widget, isA<RouteUnavailablePage>());
    });

    testWidgets('a group edit with its extra builds the form', (tester) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();
      const groupId = 'g1';
      final group = Group(
        id: groupId,
        name: 'Family',
        ownerId: 'owner',
        members: const <String>['owner'],
      );

      final widget = pageChild(
        groupFormPageEditRoute(),
        context,
        stateFixture(
          router,
          location: '/group/$groupId/edit',
          pathParameters: const <String, String>{'id': groupId},
          extra: group,
        ),
      );

      expect(widget, isA<GroupFormPage>());
    });

    testWidgets('a wrong-typed verification extra shows the invalid link', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();

      final widget = pageChild(
        verificationPageRoute(),
        context,
        stateFixture(router, location: VerificationPage.route, extra: 42),
      );
      await tester.pumpWidget(MaterialApp(home: widget));

      expect(find.text('Invalid verification link.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing invitation group shows the invalid link', (
      tester,
    ) async {
      final context = await pumpRouterContext(tester);
      final router = newRouter();

      final widget = pageChild(
        joinGroupPageRoute(),
        context,
        stateFixture(router, location: JoinGroupPage.route),
      );
      await tester.pumpWidget(MaterialApp(home: widget));

      expect(find.text('Invalid invitation link.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
