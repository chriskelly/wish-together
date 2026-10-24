import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';
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

/// Resolves the repository used for profile reads and writes.
///
/// The composition root supplies it once; tests may inject one. This is the
/// only place that may fall back to the locator, so a staging build cannot
/// accidentally construct a production repository.
UserRepository resolveUserRepository([UserRepository? injected]) =>
    injected ?? getIt<UserRepository>();

GoRouter createRouter(
  AuthService authService, {
  UserRepository? userRepository,
  String? initialLocation,
}) {
  // Resolve the repository once at composition time so every redirect uses the
  // same database target as the rest of the app.
  final repository = resolveUserRepository(userRepository);

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: AuthListenable(authService),
    redirect: (BuildContext context, GoRouterState state) =>
        handleRedirect(state.uri.toString(), authService, userRepo: repository),
    routes: <RouteBase>[
      homePageRoute(),
      loginPageRoute(),
      verificationPageRoute(),
      wishlistFormPageRoute(),
      groupFormPageRoute(),
      profilePageRoute(),
      joinGroupPageRoute(),
    ],
  );
}

Future<String?> handleRedirect(
  String uriString,
  AuthService authService, {
  UserRepository? userRepo,
}) async {
  final uri = Uri.parse(uriString);
  final loggedIn = authService.currentUserId != null;
  if (!loggedIn) {
    return _redirectIfNotLoggedIn(uri, uriString);
  }

  // --- User is Logged In ---

  // The profile document has to exist before any route can decide what to show.
  // The login redirect used to return before this, which sent a brand-new
  // account to home with no `users/{uid}` document to render.
  final user = await resolveUserRepository(userRepo).getOrCreateUser(
    authService.currentUserId!,
    email: authService.currentUserEmail,
    phoneNumber: authService.currentUserPhoneNumber,
  );
  final hasDisplayName =
      user.displayName != null && user.displayName!.isNotEmpty;

  if (uri.path == LoginPage.route) {
    return _redirectFromLogin(uri, hasDisplayName);
  }

  if (uri.path == VerificationPage.route) {
    return _redirectFromVerify(uri, hasDisplayName);
  }

  if (!hasDisplayName) {
    return _redirectToProfile(uri, uriString);
  }

  return null; // No redirect needed.
}

/// If not on the login page, redirects to it, preserving the original destination.
String? _redirectIfNotLoggedIn(Uri uri, String originalUri) {
  if (uri.path == LoginPage.route || uri.path == VerificationPage.route) {
    return null;
  }
  return '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(originalUri)}';
}

/// Redirects a signed-in user away from the login page.
///
/// A user with no display name still needs onboarding first, so they go to the
/// profile page (preserving any `redirect_to`); everyone else goes to the
/// intended destination or home.
String _redirectFromLogin(Uri uri, bool hasDisplayName) {
  final redirectTo = uri.queryParameters[redirectToParam];
  if (!hasDisplayName) {
    return redirectTo == null
        ? ProfilePage.route
        : '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(redirectTo)}';
  }
  return redirectTo ?? HomePage.route;
}

/// Redirects away from the verify page to the intended destination or home.
/// If user has no display name, redirects to profile page preserving redirect_to.
String _redirectFromVerify(Uri uri, bool hasDisplayName) {
  if (!hasDisplayName) {
    final redirectTo = uri.queryParameters[redirectToParam] ?? uri.toString();
    return '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(redirectTo)}';
  }
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

GoRoute verificationPageRoute() => GoRoute(
  path: VerificationPage.route,
  builder: (BuildContext context, GoRouterState state) {
    final verificationId = state.extra as String?;
    if (verificationId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid verification link.')),
      );
    }
    final redirectTo = state.uri.queryParameters[redirectToParam];
    return VerificationPage(
      verificationId: verificationId,
      redirectTo: redirectTo,
    );
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
