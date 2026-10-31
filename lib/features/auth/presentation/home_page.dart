import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
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

  /// The session the page is showing, captured once when the page is created.
  String? _uid;

  StreamSubscription<User>? _userSubscription;
  StreamSubscription<List<Wishlist>>? _wishlistSubscription;
  StreamSubscription<List<Group>>? _groupSubscription;

  User? _user;
  Object? _userError;
  List<Wishlist>? _wishlists;
  Object? _wishlistsError;
  List<Group>? _groups;
  Object? _groupsError;

  @override
  void initState() {
    super.initState();

    // The page's reads belong to the session that was live when it was built.
    // Without a uid there is nothing to read: the router is about to show the
    // login page, and subscribing here would race the session being cleared.
    final uid = _authService.currentUserId;
    if (uid == null) {
      return;
    }
    _uid = uid;

    _userSubscription = _userRepository
        .streamOne(uid)
        .listen(
          (user) {
            if (!mounted) return;
            setState(() {
              _user = user;
              _userError = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _userError = error);
          },
        );
    _wishlistSubscription = _wishlistRepository
        .streamWhere('ownerId', isEqualTo: uid)
        .listen(
          (wishlists) {
            if (!mounted) return;
            setState(() {
              _wishlists = wishlists;
              _wishlistsError = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _wishlistsError = error);
          },
        );
    _groupSubscription = _groupRepository
        .streamWhere('members', arrayContains: uid)
        .listen(
          (groups) {
            if (!mounted) return;
            setState(() {
              _groups = groups;
              _groupsError = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _groupsError = error);
          },
        );
  }

  @override
  void dispose() {
    _cancelDataStreams();
    super.dispose();
  }

  /// Drops every home read.
  ///
  /// Called before signing out, so no listener is attached while the session is
  /// cleared: a listener that outlives the credential is what made Firestore
  /// re-issue its reads unauthenticated and report `permission-denied` for
  /// `users`, `wishlists` and `groups`.
  void _cancelDataStreams() {
    unawaited(_userSubscription?.cancel());
    _userSubscription = null;
    unawaited(_wishlistSubscription?.cancel());
    _wishlistSubscription = null;
    unawaited(_groupSubscription?.cancel());
    _groupSubscription = null;
  }

  Future<void> _signOut() async {
    _cancelDataStreams();
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_userError != null) {
      return _userLoadError();
    }

    final user = _user;
    if (user == null) {
      return _userLoading();
    }

    return Scaffold(
      appBar: _homePageAppBar(user.displayName, context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            _dataSection<Wishlist>(
              title: 'My Wishlists',
              onAdd: () => context.push(WishlistFormPage.createRoute),
              addTooltip: 'Add new wishlist',
              items: _wishlists,
              error: _wishlistsError,
              emptyMessage: 'No wishlists yet. Create one!',
              entityWidgetBuilder: _wishlistWidgetBuilder(),
            ),
            const SizedBox(height: 24),
            _dataSection<Group>(
              title: 'My Groups',
              onAdd: () => context.push(GroupFormPage.createRoute),
              addTooltip: 'Add new group',
              items: _groups,
              error: _groupsError,
              emptyMessage: 'No groups yet. Create or join one!',
              entityWidgetBuilder: _groupWidgetBuilder(userId: _uid!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataSection<T>({
    required String title,
    required VoidCallback onAdd,
    required String addTooltip,
    required List<T>? items,
    required Object? error,
    required String emptyMessage,
    required EntityWidgetBuilder<T> entityWidgetBuilder,
  }) => DataSection(
    title: title,
    onAdd: onAdd,
    addTooltip: addTooltip,
    child: ListContentBuilder<T>(
      items: items,
      error: error,
      emptyWidget: ListEmptyPlaceholder(message: emptyMessage),
      isScrollable: false,
      entityWidgetBuilder: entityWidgetBuilder,
    ),
  );

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
        onPressed: _signOut,
      ),
    ],
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
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Confirm Deletion',
      content: 'Are you sure you want to delete this wishlist?',
      confirmText: 'Delete',
    );

    if (confirmed != true) return;

    try {
      await _wishlistRepository.delete(wishlistId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Wishlist deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

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
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Confirm Deletion',
      content: 'Are you sure you want to delete this group?',
      confirmText: 'Delete',
    );

    if (confirmed != true) return;

    try {
      await _groupRepository.delete(groupId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
