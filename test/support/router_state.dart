import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// A router that exists only to supply a [RouteConfiguration] to a
/// [GoRouterState].
///
/// The route callbacks under test read `pathParameters` and `extra`, so the
/// state is built directly instead of navigating through a router graph.
GoRouter stateFixtureRouter() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const SizedBox.shrink(),
    ),
  ],
);

/// The state a route callback receives, with only the fields routes read.
GoRouterState stateFixture(
  GoRouter router, {
  String location = '/',
  Map<String, String> pathParameters = const <String, String>{},
  Object? extra,
}) {
  return GoRouterState(
    router.configuration,
    uri: Uri.parse(location),
    matchedLocation: location,
    fullPath: location,
    pathParameters: pathParameters,
    extra: extra,
    pageKey: const ValueKey<String>('route-state-fixture'),
  );
}
