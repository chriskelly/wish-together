import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/route_error_page.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';

import '../support/router_state.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockUserRepository extends Mock implements UserRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthSession session;
  late MockUserRepository users;

  setUp(() {
    session = MockAuthSession();
    users = MockUserRepository();
    when(() => session.uidChanges)
        .thenAnswer((_) => const Stream<String?>.empty());
  });

  testWidgets('every configured route builds a Material page', (tester) async {
    final context = await pumpRouterContext(tester);
    final router = createRouter(session, userRepository: users);
    addTearDown(router.dispose);

    final withoutMaterialPage = <String>[];
    var routeCount = 0;

    void visit(List<RouteBase> routes) {
      for (final route in routes) {
        expect(
          route,
          isA<GoRoute>(),
          reason: 'the router graph holds GoRoutes',
        );
        if (route is! GoRoute) {
          continue;
        }
        routeCount++;
        final pageBuilder = route.pageBuilder;
        if (pageBuilder == null) {
          withoutMaterialPage.add('${route.path} (no pageBuilder)');
        } else {
          final page = pageBuilder(
            context,
            stateFixture(
              router,
              location: route.path,
              pathParameters: const <String, String>{'id': 'w1'},
            ),
          );
          if (page is! MaterialPage) {
            withoutMaterialPage.add(route.path);
          }
        }
        visit(route.routes);
      }
    }

    visit(router.configuration.routes);

    expect(routeCount, greaterThanOrEqualTo(13));
    expect(withoutMaterialPage, isEmpty);
  });

  testWidgets('a normal route renders through a Material page', (tester) async {
    when(() => session.currentUserId).thenReturn(null);
    final router = createRouter(
      session,
      userRepository: users,
      initialLocation: VerificationPage.route,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Invalid verification link.'), findsOneWidget);
    final navigator = tester.widgetList<Navigator>(find.byType(Navigator)).last;
    expect(navigator.pages.last, isA<MaterialPage<void>>());
  });

  testWidgets('an unknown location keeps Material error chrome', (
    tester,
  ) async {
    const uid = 'uid-1';
    when(() => session.currentUserId).thenReturn(uid);
    when(() => session.currentUserEmail).thenReturn(null);
    when(() => session.currentUserPhoneNumber).thenReturn(null);
    when(
      () => users.getOrCreateUser(
        any(),
        email: any(named: 'email'),
        phoneNumber: any(named: 'phoneNumber'),
      ),
    ).thenAnswer((_) async => User(id: uid, displayName: 'Sam'));

    final router = createRouter(
      session,
      userRepository: users,
      initialLocation: '/no-such-route',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(RouteErrorPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Page Not Found'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    final navigator = tester.widgetList<Navigator>(find.byType(Navigator)).last;
    expect(navigator.pages.last, isA<MaterialPage<void>>());
  });

  testWidgets('the error page Home action returns to the root', (tester) async {
    final router = GoRouter(
      initialLocation: '/no-such-route',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('home')),
        ),
      ],
      errorPageBuilder: (BuildContext context, GoRouterState state) =>
          MaterialPage<void>(
            key: state.pageKey,
            child: RouteErrorPage(error: state.error),
          ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}
