import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/auth/home_page.dart';
import 'package:myapp/auth/login_page.dart';
import 'package:myapp/auth/verification_page.dart';
import 'package:myapp/groups/group_details_page.dart';
import 'package:myapp/groups/group_form_page.dart';
import 'package:myapp/models/group.dart';
import 'package:myapp/models/item.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/profile/profile_page.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:myapp/wishlist/wishlist_form_page.dart';
import 'package:myapp/wishlist/wishlist_details_page.dart';
import 'package:myapp/wishlist/item_form_page.dart';

final router = GoRouter(
  redirect: (BuildContext context, GoRouterState state) async {
    final auth = FirebaseAuth.instance;
    final firestoreService = FirestoreService();

    final bool loggedIn = auth.currentUser != null;
    final bool isLoggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/verify';
    final bool isCreatingProfile = state.matchedLocation == '/profile';

    if (!loggedIn) {
      return isLoggingIn ? null : '/login';
    }

    // User is logged in, check for profile completion
    final user = auth.currentUser!;
    final appUser = await firestoreService.getUser(user.uid);

    final bool hasProfile = appUser?.displayName != null && appUser!.displayName!.isNotEmpty;

    if (loggedIn && isLoggingIn) {
      return hasProfile ? '/' : '/profile';
    }

    if (loggedIn && !hasProfile) {
        // If the user is logged in but has no profile, 
        // they must go to the profile page. They cannot navigate anywhere else.
        return isCreatingProfile ? null : '/profile';
    }
    

    return null; // No redirect needed
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
            return const ProfilePage();
        },
    ),
  ],
);
