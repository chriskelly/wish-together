import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/auth/home_page.dart';
import 'package:myapp/auth/login_page.dart';
import 'package:myapp/auth/verification_page.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/wishlist/wishlist_form_page.dart';
import 'package:myapp/wishlist/wishlist_details_page.dart';
import 'package:myapp/wishlist/item_form_page.dart';

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
      routes: [
        GoRoute(
          path: 'wishlist/:id',
          builder: (BuildContext context, GoRouterState state) {
            final wishlistId = state.pathParameters['id']!;
            return WishlistDetailsPage(wishlistId: wishlistId);
          },
          routes: [
            GoRoute(
              path: 'add-item',
              builder: (BuildContext context, GoRouterState state) {
                final wishlistId = state.pathParameters['id']!;
                return ItemFormPage(wishlistId: wishlistId);
              },
            ),
            GoRoute(
              path: 'edit',
              builder: (BuildContext context, GoRouterState state) {
                final wishlist = state.extra as Wishlist;
                return WishlistFormPage(wishlist: wishlist);
              },
            ),
            GoRoute(
              path: 'item/:itemId/edit',
              builder: (BuildContext context, GoRouterState state) {
                final wishlistId = state.pathParameters['id']!;
                final item = state.extra as Item;
                return ItemFormPage(wishlistId: wishlistId, item: item);
              },
            ),
          ],
        ),
      ],
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
    GoRoute(
      path: '/create-wishlist',
      builder: (BuildContext context, GoRouterState state) {
        return const WishlistFormPage();
      },
    ),
  ],
);
