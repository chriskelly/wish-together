import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

import '../data/auth_service.dart';

class HomePage extends StatefulWidget {
  static const String route = '/';
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = getIt<AuthService>();
  final UserRepository _userRepository = getIt<UserRepository>();
  final WishlistRepository _wishlistRepository = getIt<WishlistRepository>();
  final GroupRepository _groupRepository = getIt<GroupRepository>();

  @override
  Widget build(BuildContext context) {
    final authUserId = _authService.currentUserId!;

    return StreamBuilder<User?>(
      stream: _userRepository.streamOne(authUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _userLoading();
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return _userLoadError();
        }

        final user = snapshot.data!;
        return Scaffold(
          appBar: _homePageAppBar(user.displayName, context),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _wishlistDataSection(context, authUserId),
                const SizedBox(height: 24),
                _groupDataSection(context, authUserId),
              ],
            ),
          ),
        );
      },
    );
  }

  Scaffold _userLoading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  Scaffold _userLoadError() => Scaffold(
    appBar: AppBar(title: const Text('Home')),
    body: const Center(child: Text('Could not load user profile.')),
  );

  AppBar _homePageAppBar(String? displayName, BuildContext context) => AppBar(
    title: Text(
      'Welcome, ${displayName ?? 'Friend'}!',
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.person_outline),
        tooltip: 'Profile',
        onPressed: () => context.go(ProfilePage.route),
      ),
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Logout',
        onPressed: () async => await _authService.signOut(),
      ),
    ],
  );

  Widget _wishlistDataSection(BuildContext context, String userId) =>
      DataSectionBuilder<Wishlist>(
        title: 'My Wishlists',
        onAdd: () => context.push(WishlistFormPage.createRoute),
        stream: _wishlistRepository.streamWhere('ownerId', isEqualTo: userId),
        emptyListMessage: 'No wishlists yet. Create one!',
        entityWidgetBuilder: _wishlistWidgetBuilder(),
      );

  EntityWidgetBuilder<Wishlist> _wishlistWidgetBuilder() =>
      (context, wishlist) => Card(
        child: ListTile(
          title: Text(wishlist.name),
          trailing: ListItemActions(
            onDelete: () => _deleteWishlistDialog(wishlist.id!),
            deleteTooltip: 'Delete Wishlist',
          ),
          onTap: () => context.goNamed(
            WishlistDetailsPage.routeName,
            pathParameters: {'id': wishlist.id!},
          ),
        ),
      );

  Future<void> _deleteWishlistDialog(String wishlistId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this wishlist?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _wishlistRepository.delete(wishlistId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Wishlist deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _groupDataSection(BuildContext context, String userId) =>
      DataSectionBuilder<Group>(
        title: 'My Groups',
        onAdd: () => context.push(GroupFormPage.createRoute),
        stream: _groupRepository.streamWhere('members', arrayContains: userId),
        emptyListMessage: 'No groups yet. Create or join one!',
        entityWidgetBuilder: _groupWidgetBuilder(userId: userId),
      );

  EntityWidgetBuilder<Group> _groupWidgetBuilder({required String userId}) =>
      (context, group) {
        final isOwner = group.ownerId == userId;
        return Card(
          child: ListTile(
            title: Text(group.name),
            trailing: isOwner
                ? ListItemActions(
                    onDelete: () => _deleteGroup(group.id!),
                    deleteTooltip: 'Delete Group',
                  )
                : null,
            onTap: () => context.goNamed(
              GroupDetailsPage.routeName,
              pathParameters: {'id': group.id!},
            ),
          ),
        );
      };

  Future<void> _deleteGroup(String groupId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this group?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _groupRepository.delete(groupId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
