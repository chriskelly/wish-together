import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';

class AuthListenable extends ChangeNotifier {
  final AuthService authService;
  late final Stream<firebase_auth.User?> _stream;

  AuthListenable(this.authService) {
    _stream = authService.authStateChanges;
    _stream.listen((user) => notifyListeners());
  }
}

GoRouter createRouter(AuthService authService) {
  return GoRouter(
    refreshListenable: AuthListenable(authService),
    redirect: (BuildContext context, GoRouterState state) async {
      final loggedIn = authService.currentUser != null;
      final loggingIn = state.uri.toString() == '/login';

      if (!loggedIn) {
        return loggingIn ? null : '/login';
      }

      // -- User is logged in --

      final userRepo = UserRepository();
      final authUser = authService.currentUser!;
      final user = await userRepo.getOrCreateUser(
        authUser.uid,
        email: authUser.email,
        // displayName: authUser.displayName,
      );
      final hasProfile =
          user.displayName != null && user.displayName!.isNotEmpty;
      final creatingProfile = state.uri.toString().startsWith('/profile');

      if (!hasProfile && !creatingProfile) {
        return '/profile';
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
            return const Scaffold(
              body: Center(child: Text('Invalid invitation link.')),
            );
          }
          return JoinGroupPage(groupId: groupId);
        },
      ),
    ],
  );
}
