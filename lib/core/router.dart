import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/features/auth/presentation/home_page.dart';
import 'package:myapp/features/auth/presentation/login_page.dart';
import 'package:myapp/features/auth/presentation/verification_page.dart';
import 'package:myapp/features/group/presentation/group_details_page.dart';
import 'package:myapp/features/group/presentation/group_form_page.dart';
import 'package:myapp/features/group/presentation/join_group_page.dart';
import 'package:myapp/features/group/domain/group.dart';
import 'package:myapp/features/wishlist/domain/item.dart';
import 'package:myapp/features/wishlist/domain/wishlist.dart';
import 'package:myapp/features/auth/presentation/profile_page.dart';
import 'package:myapp/core/services/firestore_service.dart';
import 'package:myapp/features/wishlist/presentation/wishlist_form_page.dart';
import 'package:myapp/features/wishlist/presentation/wishlist_details_page.dart';
import 'package:myapp/features/wishlist/presentation/item_form_page.dart';

final router = GoRouter(
  redirect: (BuildContext context, GoRouterState state) async {
    final auth = FirebaseAuth.instance;
    final firestoreService = FirestoreService();

    final bool loggedIn = auth.currentUser != null;
    final String location = state.uri.toString();
    final isAuthFlow = location.startsWith('/login') || location.startsWith('/verify');

    // 1. Handle user not logged in
    if (!loggedIn) {
      return isAuthFlow ? null : '/login';
    }

    // --- User is logged in ---

    // 2. Handle profile creation for new users
    final user = auth.currentUser!;
    final appUser = await firestoreService.getUser(user.uid);
    final bool hasProfile = appUser?.displayName != null && appUser!.displayName!.isNotEmpty;

    if (isAuthFlow) {
        return '/'; // Logged-in users shouldn't be in the auth flow.
    }

    if (!hasProfile) {
      final isCreatingProfile = location.startsWith('/profile');
      if (isCreatingProfile) {
        return null;
      }
      // Preserve the intended destination after profile creation.
      return '/profile?redirect_to=$location';
    }

    // --- User is logged in and has a profile ---
    return null; // No redirect needed, proceed to the original location.
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
        GoRoute(
          path: 'group/:id',
          builder: (BuildContext context, GoRouterState state) {
            final groupId = state.pathParameters['id']!;
            return GroupDetailsPage(groupId: groupId);
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (BuildContext context, GoRouterState state) {
                final group = state.extra as Group;
                return GroupFormPage(group: group);
              },
            ),
          ]
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
     GoRoute(
      path: '/create-group',
      builder: (BuildContext context, GoRouterState state) {
        return const GroupFormPage();
      },
    ),
    GoRoute(
        path: '/profile',
        builder: (BuildContext context, GoRouterState state) {
          final redirectTo = state.uri.queryParameters['redirect_to'];
          return ProfilePage(redirectTo: redirectTo);
        },
    ),
    GoRoute(
        path: '/join',
        builder: (BuildContext context, GoRouterState state) {
            final groupId = state.uri.queryParameters['group'];
            if (groupId == null) {
                return const Scaffold(body: Center(child: Text('Invalid invitation link.')));
            }
            return JoinGroupPage(groupId: groupId);
        },
    ),
  ],
);
