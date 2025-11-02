import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
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
  final _authService = AuthService();
  final _userRepository = UserRepository();
  final _wishlistRepository = WishlistRepository();
  final _groupRepository = GroupRepository();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<auth.User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final authUser = snapshot.data;
        if (authUser == null) {
          return _buildLoggedOutView(context);
        } else {
          return _buildLoggedInView(context, authUser);
        }
      },
    );
  }

  Widget _buildLoggedOutView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WishTogether')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Welcome to WishTogether!',
                style: Theme.of(context).textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go(LoginPage.route),
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWishlist(String wishlistId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text(
            'Are you sure you want to delete this wishlist? This action cannot be undone.',
          ),
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
        );
      },
    );

    if (confirmed == true) {
      try {
        await _wishlistRepository.delete(wishlistId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Wishlist deleted.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting wishlist: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteGroup(String groupId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text(
            'Are you sure you want to delete this group? This action cannot be undone.',
          ),
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
        );
      },
    );

    if (confirmed == true) {
      try {
        await _groupRepository.delete(groupId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Group deleted.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting group: $e')));
        }
      }
    }
  }

  Widget _buildLoggedInView(BuildContext context, auth.User authUser) {
    return FutureBuilder<User?>(
      future: _userRepository.get(authUser.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading Profile...')),
            body: const Center(child: Text('Could not load user profile.')),
          );
        }

        final user = snapshot.data!;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Welcome, ${user.displayName}!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Profile',
                onPressed: () {
                  context.go(ProfilePage.route);
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () async {
                  await _authService.signOut();
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _buildDataSection<Wishlist>(
                    context: context,
                    title: 'My Wishlists',
                    onAdd: () => context.push(WishlistFormPage.createRoute),
                    stream: _wishlistRepository.streamWhere(
                      'ownerId',
                      isEqualTo: authUser.uid,
                    ),
                    emptyListMessage: 'No wishlists yet. Create one!',
                    itemBuilder: (context, wishlist) {
                      return Card(
                        child: ListTile(
                          title: Text(wishlist.name),
                          trailing: ListItemActions(
                            onDelete: () => _deleteWishlist(wishlist.id!),
                            deleteTooltip: 'Delete Wishlist',
                          ),
                          onTap: () {
                            context.goNamed(
                              WishlistDetailsPage.routeName,
                              pathParameters: {'id': wishlist.id!},
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildDataSection<Group>(
                    context: context,
                    title: 'My Groups',
                    onAdd: () {
                      context.push(GroupFormPage.createRoute);
                    },
                    stream: _groupRepository.streamWhere(
                      'members',
                      arrayContains: authUser.uid,
                    ),
                    emptyListMessage: 'No groups yet. Create or join one!',
                    itemBuilder: (context, group) {
                      final isOwner = group.ownerId == authUser.uid;
                      return Card(
                        child: ListTile(
                          title: Text(group.name),
                          trailing: isOwner
                              ? ListItemActions(
                                  onDelete: () => _deleteGroup(group.id!),
                                  deleteTooltip: 'Delete Group',
                                )
                              : null,
                          onTap: () {
                            context.goNamed(
                              GroupDetailsPage.routeName,
                              pathParameters: {'id': group.id!},
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDataSection<T>({
    required BuildContext context,
    required String title,
    required VoidCallback onAdd,
    required Stream<List<T>> stream,
    required String emptyListMessage,
    required ItemWidgetBuilder<T> itemBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onAdd,
              tooltip: 'Create new',
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamListBuilder<T>(
          stream: stream,
          itemBuilder: itemBuilder,
          isScrollable: false,
          emptyWidget: Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                emptyListMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
