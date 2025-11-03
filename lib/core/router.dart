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

Future<String?> handleRedirect(String uri, AuthService authService,
    {UserRepository? userRepo}) async {
  userRepo ??= UserRepository();
  final loggedIn = authService.currentUser != null;
  final loggingIn = uri == LoginPage.route;

  if (!loggedIn) {
    return loggingIn ? null : LoginPage.route;
  }

  // -- User is logged in --

  final authUser = authService.currentUser!;
  final user = await userRepo.getOrCreateUser(
    authUser.uid,
    email: authUser.email,
    // displayName: authUser.displayName,
  );
  final hasProfile = user.displayName != null && user.displayName!.isNotEmpty;
  final creatingProfile = uri.startsWith(ProfilePage.route);

  if (!hasProfile && !creatingProfile) {
    return ProfilePage.route;
  }

  if (loggingIn) {
    return HomePage.route;
  }

  return null;
}

GoRouter createRouter(AuthService authService) {
  return GoRouter(
    refreshListenable: AuthListenable(authService),
    redirect: (BuildContext context, GoRouterState state) =>
        handleRedirect(state.uri.toString(), authService),
    routes: <RouteBase>[
      GoRoute(
        path: HomePage.route,
        builder: (BuildContext context, GoRouterState state) {
          return const HomePage();
        },
        routes: [
          GoRoute(
            name: WishlistDetailsPage.routeName,
            path: WishlistDetailsPage.route.substring(1), // remove leading '/'
            builder: (BuildContext context, GoRouterState state) {
              final wishlistId = state.pathParameters['id']!;
              return WishlistDetailsPage(wishlistId: wishlistId);
            },
            routes: [
              GoRoute(
                name: ItemFormPage.createRouteName,
                path: ItemFormPage.createRoute,
                builder: (BuildContext context, GoRouterState state) {
                  final wishlistId = state.pathParameters['id']!;
                  return ItemFormPage(wishlistId: wishlistId);
                },
              ),
              GoRoute(
                name: WishlistFormPage.editRouteName,
                path: WishlistFormPage.editRoute,
                builder: (BuildContext context, GoRouterState state) {
                  final wishlist = state.extra as Wishlist;
                  return WishlistFormPage(wishlist: wishlist);
                },
              ),
              GoRoute(
                name: ItemFormPage.editRouteName,
                path: ItemFormPage.editRoute,
                builder: (BuildContext context, GoRouterState state) {
                  final wishlistId = state.pathParameters['id']!;
                  final item = state.extra as Item;
                  return ItemFormPage(wishlistId: wishlistId, item: item);
                },
              ),
            ],
          ),
          GoRoute(
            name: GroupDetailsPage.routeName,
            path: GroupDetailsPage.route.substring(1), // remove leading '/'
            builder: (BuildContext context, GoRouterState state) {
              final groupId = state.pathParameters['id']!;
              return GroupDetailsPage(groupId: groupId);
            },
            routes: [
              GoRoute(
                name: GroupFormPage.editRouteName,
                path: GroupFormPage.editRoute,
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
        path: LoginPage.route,
        builder: (BuildContext context, GoRouterState state) {
          return const LoginPage();
        },
      ),
      GoRoute(
        path: WishlistFormPage.createRoute,
        builder: (BuildContext context, GoRouterState state) {
          return const WishlistFormPage();
        },
      ),
      GoRoute(
        path: GroupFormPage.createRoute,
        builder: (BuildContext context, GoRouterState state) {
          return const GroupFormPage();
        },
      ),
      GoRoute(
        path: ProfilePage.route,
        builder: (BuildContext context, GoRouterState state) {
          final redirectTo = state.uri.queryParameters['redirect_to'];
          return ProfilePage(redirectTo: redirectTo);
        },
      ),
      GoRoute(
        name: JoinGroupPage.routeName,
        path: JoinGroupPage.route,
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
