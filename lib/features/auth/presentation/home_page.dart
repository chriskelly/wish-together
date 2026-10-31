import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
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

  /// The session the page is showing, captured when its reads start.
  String? _uid;

  StreamSubscription<User>? _userSubscription;
  StreamSubscription<List<Wishlist>>? _wishlistSubscription;
  StreamSubscription<List<Group>>? _groupSubscription;

  User? _user;
  Object? _userError;
  bool _userStreamEnded = false;
  List<Wishlist>? _wishlists;
  Object? _wishlistsError;
  List<Group>? _groups;
  Object? _groupsError;

  /// Guards against a second tap while a sign-out is already in flight.
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _subscribeDataStreams();
  }

  @override
  void dispose() {
    _cancelDataStreams();
    super.dispose();
  }

  /// Starts the three reads that belong to the current session.
  ///
  /// Called when the page is created and again if a sign-out fails while the
  /// session survives. Nothing is read without a uid: on the first call the
  /// router is about to show the login page, and a read here would race the
  /// session being cleared.
  void _subscribeDataStreams() {
    // A start always replaces whatever a previous lifecycle left behind. The
    // callers already cancel first; this keeps a future caller safe.
    _cancelDataStreams();

    final uid = _authService.currentUserId;
    if (uid == null) {
      return;
    }
    _uid = uid;
    // A start begins with no result and no failure for any of the three reads,
    // so a restarted lifecycle cannot show the previous one's error.
    _userError = null;
    _userStreamEnded = false;
    _wishlistsError = null;
    _groupsError = null;

    _userSubscription = _listen<User>(
      _userRepository.streamOne(uid),
      (user) => setState(() {
        _user = user;
        _userError = null;
      }),
      (error) => setState(() => _userError = error),
      onDone: () => setState(() => _userStreamEnded = true),
    );
    _wishlistSubscription = _listen<List<Wishlist>>(
      _wishlistRepository.streamWhere('ownerId', isEqualTo: uid),
      (wishlists) => setState(() {
        _wishlists = wishlists;
        _wishlistsError = null;
      }),
      (error) => setState(() => _wishlistsError = error),
      onDone: () => setState(() => _wishlists ??= const <Wishlist>[]),
    );
    _groupSubscription = _listen<List<Group>>(
      _groupRepository.streamWhere('members', arrayContains: uid),
      (groups) => setState(() {
        _groups = groups;
        _groupsError = null;
      }),
      (error) => setState(() => _groupsError = error),
      onDone: () => setState(() => _groups ??= const <Group>[]),
    );
  }

  /// Subscribes, dropping any event that arrives after the page is gone.
  StreamSubscription<T> _listen<T>(
    Stream<T> stream,
    void Function(T value) onValue,
    void Function(Object error) onError, {
    required void Function() onDone,
  }) {
    return stream.listen(
      (value) {
        if (!mounted) return;
        onValue(value);
      },
      onError: (Object error) {
        if (!mounted) return;
        onError(error);
      },
      onDone: () {
        if (!mounted) return;
        onDone();
      },
    );
  }

  /// Drops every home read.
  ///
  /// Called before signing out, so no listener is attached while the session is
  /// cleared: a listener that outlives the credential is what made Firestore
  /// re-issue its reads unauthenticated and report `permission-denied` for
  /// `users`, `wishlists` and `groups`. The guarantee is at the Dart
  /// subscription level, which is where the SDK's read is issued from.
  void _cancelDataStreams() {
    unawaited(_userSubscription?.cancel());
    _userSubscription = null;
    unawaited(_wishlistSubscription?.cancel());
    _wishlistSubscription = null;
    unawaited(_groupSubscription?.cancel());
    _groupSubscription = null;
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    _signingOut = true;
    _cancelDataStreams();
    try {
      await _authService.signOut();
    } catch (error, stackTrace) {
      appLogOrNull?.error(error, stackTrace, code: 'sign-out-failed');
      if (!mounted) return;

      if (_authService.currentUserId == null) {
        // The sign-out cleared the session before it failed: there is nothing
        // left to read, so drop everything that belonged to the dead session
        // and let the router take the page away.
        setState(() {
          _uid = null;
          _user = null;
          _wishlists = null;
          _groups = null;
        });
        return;
      }

      // The session is still live, so the page has to keep working. Report the
      // failure before restarting, so a restart that throws stays loud instead
      // of vanishing behind a caught error.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
      setState(_subscribeDataStreams);
    } finally {
      _signingOut = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final uid = _uid;

    if (_userError != null || (_userStreamEnded && user == null)) {
      return _userLoadError();
    }
    if (user == null || uid == null) {
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
              entityWidgetBuilder: _groupWidgetBuilder(userId: uid),
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
