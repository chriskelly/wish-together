import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';

void main() {
  group('shouldShowProfileBackButton', () {
    test('offers the way out to a loaded existing user', () {
      expect(
        shouldShowProfileBackButton(isLoading: false, isNewUser: false),
        isTrue,
      );
    });

    test('keeps a new user in onboarding', () {
      expect(
        shouldShowProfileBackButton(isLoading: false, isNewUser: true),
        isFalse,
      );
    });

    test('waits for the profile to load', () {
      expect(
        shouldShowProfileBackButton(isLoading: true, isNewUser: false),
        isFalse,
      );
    });

    test('offers nothing while a new user is still loading', () {
      expect(
        shouldShowProfileBackButton(isLoading: true, isNewUser: true),
        isFalse,
      );
    });
  });

  group('profileExitTarget', () {
    test('returns the destination the user was headed for', () {
      const wishlistId = 'abc';
      final destination = '/wishlist/$wishlistId';

      expect(profileExitTarget(destination), destination);
    });

    test('keeps an invitation path intact', () {
      const groupId = '123';
      final invitation = '${JoinGroupPage.route}?group=$groupId';

      expect(profileExitTarget(invitation), invitation);
    });

    test('falls back to home without a destination', () {
      expect(profileExitTarget(null), HomePage.route);
    });

    test('falls back to home for a blank destination', () {
      expect(profileExitTarget(''), HomePage.route);
    });

    test('falls back to home for a whitespace-only destination', () {
      expect(profileExitTarget('   '), HomePage.route);
    });

    test('falls back to home when the destination is the profile page', () {
      expect(profileExitTarget(ProfilePage.route), HomePage.route);
    });

    test('falls back to home for the profile page with a trailing slash', () {
      expect(profileExitTarget('${ProfilePage.route}/'), HomePage.route);
    });

    test('falls back to home for the profile page with a query string', () {
      expect(
        profileExitTarget('${ProfilePage.route}?redirect_to=%2F'),
        HomePage.route,
      );
    });
  });
}
