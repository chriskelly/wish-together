import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_hero.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/core/design_tokens.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/presentation/home_group_row.dart';
import 'package:wishtogether/features/auth/presentation/home_wishlist_row.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/auth/presentation/providers/home_providers.dart';
import 'package:wishtogether/features/auth/presentation/providers/home_sign_out_provider.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

class HomePage extends ConsumerWidget {
  static const String route = '/';
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      // Nothing is readable without a session; the router is about to show the
      // login page.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // A closed gate is the sign-out path. It is checked before the values
    // because a closed read emits data (null / empty), not loading.
    if (!ref.watch(homeReadsEnabledProvider)) {
      return _loading(context, ref);
    }

    final userAsync = ref.watch(homeUserProvider(userId));
    final wishlistsAsync = ref.watch(homeWishlistsProvider(userId));
    final groupsAsync = ref.watch(homeGroupsProvider(userId));

    // AsyncValue keeps the previous user while an error is showing, and the
    // page has always treated a failed profile read as final until a restart.
    if (userAsync.hasError) return _userLoadError();
    if (userAsync.isLoading) return _loading(context, ref);
    final user = userAsync.value;
    if (user == null) return _userLoadError();

    return Scaffold(
      body: Column(
        children: [
          BrandHero(
            title: 'Welcome,\n${user.displayName ?? 'Friend'}!',
            titleStyle: heroHomeTextStyle,
            actions: _homeActions(context, ref),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BrandGeometry.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: BrandGeometry.spacingLg),
                  _wishlistsSection(context, wishlistsAsync),
                  const SizedBox(height: BrandGeometry.sectionGap),
                  _groupsSection(context, groupsAsync, userId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The profile and sign-out controls, kept in the hero so the greeting and
  /// its actions stay reachable while the lists scroll.
  ///
  /// The loading scaffold reuses them: a first load, a sign-out in flight and a
  /// restart after a failed sign-out all keep the profile and sign-out controls
  /// reachable, and the command ignores a tap while one is already in flight.
  List<Widget> _homeActions(BuildContext context, WidgetRef ref) => <Widget>[
    IconButton(
      icon: const Icon(Icons.person_outline),
      tooltip: 'Profile',
      onPressed: () => context.go(ProfilePage.route),
    ),
    // Only offer sign-out when the session has a sign-in flow behind it.
    if (ref.watch(authSessionProvider).supportsSignOut)
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Logout',
        onPressed: () => _signOut(context, ref),
      ),
  ];

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(homeSignOutProvider.notifier).signOut();
    if (result != HomeSignOutResult.failedSessionLive || !context.mounted) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not sign out. Please try again.')),
    );
  }

  Widget _wishlistsSection(
    BuildContext context,
    AsyncValue<List<Wishlist>> wishlistsAsync,
  ) => DataSection(
    title: 'My Wishlists',
    onAdd: () => context.push(WishlistFormPage.createRoute),
    addTooltip: 'Add new wishlist',
    child: ListContentBuilder<Wishlist>(
      // A refresh keeps the previous value; the section shows loading instead
      // of a stale list until the new subscription delivers.
      items: wishlistsAsync.isLoading ? null : wishlistsAsync.value,
      error: wishlistsAsync.error,
      emptyWidget: const ListEmptyPlaceholder(
        message: 'No wishlists yet. Create one!',
      ),
      isScrollable: false,
      entityWidgetBuilder: (context, wishlist) =>
          HomeWishlistRow(key: ValueKey(wishlist.id), wishlist: wishlist),
    ),
  );

  Widget _groupsSection(
    BuildContext context,
    AsyncValue<List<Group>> groupsAsync,
    String userId,
  ) => DataSection(
    title: 'My Groups',
    onAdd: () => context.push(GroupFormPage.createRoute),
    addTooltip: 'Add new group',
    child: ListContentBuilder<Group>(
      items: groupsAsync.isLoading ? null : groupsAsync.value,
      error: groupsAsync.error,
      emptyWidget: const ListEmptyPlaceholder(
        message: 'No groups yet. Create or join one!',
      ),
      isScrollable: false,
      entityWidgetBuilder: (context, group) =>
          HomeGroupRow(key: ValueKey(group.id), group: group, userId: userId),
    ),
  );

  Widget _loading(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Home'),
      actions: _homeActions(context, ref),
    ),
    body: const Center(child: CircularProgressIndicator()),
  );

  Widget _userLoadError() => Scaffold(
    appBar: AppBar(title: const Text('Home')),
    body: const Center(child: Text('Could not load user profile.')),
  );
}
