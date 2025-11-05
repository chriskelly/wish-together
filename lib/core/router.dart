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

// The query parameter used for redirects.
const String redirectToParam = 'redirect_to';

class AuthListenable extends ChangeNotifier {
  final AuthService authService;
  late final Stream<firebase_auth.User?> _stream;

  AuthListenable(this.authService) {
    _stream = authService.authStateChanges;
    _stream.listen((user) => notifyListeners());
  }
}

GoRouter createRouter(AuthService authService) => GoRouter(
      refreshListenable: AuthListenable(authService),
      redirect: (BuildContext context, GoRouterState state) =>
          handleRedirect(state.uri.toString(), authService),
      routes: <RouteBase>[
        homePageRoute(),
        loginPageRoute(),
        wishlistFormPageRoute(),
        groupFormPageRoute(),
        profilePageRoute(),
        joinGroupPageRoute(),
      ],
    );

Future<String?> handleRedirect(
  String uriString,
  AuthService authService, {
  UserRepository? userRepo,
}) async {
  final uri = _normalizeUri(uriString);
  final loggedIn = authService.currentUser != null;
  if (!loggedIn) {
    return _redirectIfNotLoggedIn(uri, uriString);
  }

  // --- User is Logged In ---

  if (uri.path == LoginPage.route) {
    return _redirectFromLogin(uri);
  }

  final user = await (userRepo ?? UserRepository()).getOrCreateUser(
    authService.currentUser!.uid,
    email: authService.currentUser!.email,
  );
  final hasDisplayName = user.displayName != null && user.displayName!.isNotEmpty;
  if (!hasDisplayName) {
    return _redirectToProfile(uri, uriString);
  }

  return null; // No redirect needed.
}

/// Normalizes a URI string for web hash URLs.
Uri _normalizeUri(String uriString) {
  final Uri parsedForFragment = Uri.parse(uriString);
  final String effectiveUriString =
      (parsedForFragment.hasFragment && parsedForFragment.fragment.startsWith('/'))
          ? parsedForFragment.fragment
          : uriString;
  return Uri.parse(effectiveUriString);
}

/// If not on the login page, redirects to it, preserving the original destination.
String? _redirectIfNotLoggedIn(Uri uri, String originalUri) {
  if (uri.path == LoginPage.route) return null;
  return '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(originalUri)}';
}

/// Redirects away from the login page to the intended destination or home.
String _redirectFromLogin(Uri uri) {
  return uri.queryParameters[redirectToParam] ?? HomePage.route;
}

/// If not on the profile page, redirects to it, preserving the redirect destination.
String? _redirectToProfile(Uri uri, String originalUri) {
  if (uri.path == ProfilePage.route) return null;
  final redirectTo = uri.queryParameters[redirectToParam] ?? originalUri;
  return '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(redirectTo)}';
}

GoRoute homePageRoute() => GoRoute(
      path: HomePage.route,
      builder: (BuildContext context, GoRouterState state) => const HomePage(),
      routes: [wishlistDetailsPageRoute(), groupDetailsPageRoute()],
    );

GoRoute wishlistDetailsPageRoute() => GoRoute(
      name: WishlistDetailsPage.routeName,
      path: WishlistDetailsPage.route.substring(1),
      builder: (BuildContext context, GoRouterState state) {
        final wishlistId = state.pathParameters['id']!;
        return WishlistDetailsPage(wishlistId: wishlistId);
      },
      routes: [
        itemFormPageCreateRoute(),
        wishlistFormPageEditRoute(),
        itemFormPageEditRoute(),
      ],
    );

GoRoute itemFormPageCreateRoute() => GoRoute(
      name: ItemFormPage.createRouteName,
      path: ItemFormPage.createRoute,
      builder: (BuildContext context, GoRouterState state) {
        final wishlistId = state.pathParameters['id']!;
        return ItemFormPage(wishlistId: wishlistId);
      },
    );

GoRoute wishlistFormPageEditRoute() => GoRoute(
      name: WishlistFormPage.editRouteName,
      path: WishlistFormPage.editRoute,
      builder: (BuildContext context, GoRouterState state) {
        final wishlist = state.extra as Wishlist;
        return WishlistFormPage(wishlist: wishlist);
      },
    );

GoRoute itemFormPageEditRoute() => GoRoute(
      name: ItemFormPage.editRouteName,
      path: ItemFormPage.editRoute,
      builder: (BuildContext context, GoRouterState state) {
        final wishlistId = state.pathParameters['id']!;
        final item = state.extra as Item;
        return ItemFormPage(wishlistId: wishlistId, item: item);
      },
    );

GoRoute groupDetailsPageRoute() => GoRoute(
      name: GroupDetailsPage.routeName,
      path: GroupDetailsPage.route.substring(1),
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
    );

GoRoute loginPageRoute() => GoRoute(
      path: LoginPage.route,
      builder: (BuildContext context, GoRouterState state) {
        return const LoginPage();
      },
    );

GoRoute wishlistFormPageRoute() => GoRoute(
      path: WishlistFormPage.createRoute,
      builder: (BuildContext context, GoRouterState state) {
        return const WishlistFormPage();
      },
    );

GoRoute groupFormPageRoute() => GoRoute(
      path: GroupFormPage.createRoute,
      builder: (BuildContext context, GoRouterState state) {
        return const GroupFormPage();
      },
    );

GoRoute profilePageRoute() => GoRoute(
      path: ProfilePage.route,
      builder: (BuildContext context, GoRouterState state) {
        final redirectTo = state.uri.queryParameters[redirectToParam];
        return ProfilePage(redirectTo: redirectTo);
      },
    );

GoRoute joinGroupPageRoute() => GoRoute(
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
    );
