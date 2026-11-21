import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Reads a navigation extra as [T], or null when the navigation carried none.
///
/// The extra is not part of the URL. go_router serialises the route match list
/// into the route information state, and a value it cannot encode — a leave
/// guard or a domain object — becomes null on restore, including the refresh
/// after an auth change. Every route therefore reads its extra through this
/// helper and has a fallback for null; a direct cast throws during build.
T? routeExtra<T>(GoRouterState state) {
  final extra = state.extra;
  return extra is T ? extra : null;
}

/// Copy for [RouteUnavailablePage].
const String routeUnavailableMessage =
    "This page can't be reopened. Go back and try again.";

/// Shown when a route can only be rebuilt from an extra that is gone.
///
/// A normal deep link or reload is sent away by the route's redirect; this page
/// is the last resort for a restore that reaches the builder anyway. It never
/// navigates on its own, so it cannot loop.
class RouteUnavailablePage extends StatelessWidget {
  const RouteUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text(routeUnavailableMessage)));
  }
}
