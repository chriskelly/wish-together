import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

/// Every page route constant that can appear in a location.
///
/// `routeName` values are excluded on purpose: they are `GoRouterState.name`s,
/// not path segments, and are never passed to `redactRoute`.
const List<String> pageRoutes = <String>[
  HomePage.route,
  LoginPage.route,
  VerificationPage.route,
  ProfilePage.route,
  JoinGroupPage.route,
  WishlistDetailsPage.route,
  WishlistFormPage.createRoute,
  WishlistFormPage.editRoute,
  ItemFormPage.createRoute,
  ItemFormPage.editRoute,
  GroupDetailsPage.route,
  GroupFormPage.createRoute,
  GroupFormPage.editRoute,
];

void main() {
  test('every page route literal is in the redaction allowlist', () {
    final missing = <String>{};
    for (final route in pageRoutes) {
      for (final segment in route.split('/')) {
        if (segment.isEmpty || segment.startsWith(':')) {
          continue;
        }
        if (!logRouteLiterals.contains(segment)) {
          missing.add(segment);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Add the missing segments to logRouteLiterals; otherwise a real '
          'route is silently reported as :id.',
    );
  });
}
