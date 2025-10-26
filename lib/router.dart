import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth/home_page.dart';
import 'auth/login_page.dart';
import 'auth/verification_page.dart';

final GoRouter router = GoRouter(
  redirect: (BuildContext context, GoRouterState state) {
    final bool loggedIn = FirebaseAuth.instance.currentUser != null;
    final bool loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/verify';

    if (!loggedIn) {
      return loggingIn ? null : '/login';
    }

    if (loggingIn) {
      return '/';
    }

    return null;
  },
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const HomePage();
      },
    ),
    GoRoute(
      path: '/login',
      builder: (BuildContext context, GoRouterState state) {
        return const LoginPage();
      },
    ),
    GoRoute(
      path: '/verify',
      builder: (BuildContext context, GoRouterState state) {
        return VerificationPage(verificationId: state.extra as String);
      },
    ),
  ],
);
