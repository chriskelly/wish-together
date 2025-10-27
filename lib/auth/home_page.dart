import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/models/group.dart';
import 'package:myapp/models/user.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/services/firestore_service.dart';

import 'auth_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

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

        final user = snapshot.data;
        if (user == null) {
          return _buildLoggedOutView(context);
        } else {
          return _buildLoggedInView(context, user);
        }
      },
    );
  }

  Widget _buildLoggedOutView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WishTogether'),
      ),
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
                onPressed: () => context.go('/login'),
                child: const Text('Login with Phone'),
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
              'Are you sure you want to delete this wishlist? This action cannot be undone.'),
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
        await _firestoreService.deleteWishlist(wishlistId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wishlist deleted.')),
          );
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
              'Are you sure you want to delete this group? This action cannot be undone.'),
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
        await _firestoreService.deleteGroup(groupId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting group: $e')),
          );
        }
      }
    }
  }


  Widget _buildLoggedInView(BuildContext context, auth.User user) {
    return FutureBuilder<AppUser?>(
      future: _firestoreService.getUser(user.uid),
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

        final appUser = snapshot.data!;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Welcome, ${appUser.displayName}!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Profile',
                onPressed: () {
                  context.go('/profile');
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
                    onAdd: () => context.push('/create-wishlist'),
                    stream: _firestoreService.getUserWishlists(user.uid),
                    emptyListMessage: 'No wishlists yet. Create one!',
                    itemBuilder: (wishlist) {
                      return Card(
                        child: ListTile(
                          title: Text(wishlist.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () {
                                  context.push('/wishlist/${wishlist.id}/edit',
                                      extra: wishlist);
                                },
                                tooltip: 'Edit Wishlist',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () => _deleteWishlist(wishlist.id!),
                                tooltip: 'Delete Wishlist',
                              ),
                            ],
                          ),
                          onTap: () {
                            context.go('/wishlist/${wishlist.id}');
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
                       context.push('/create-group');
                    },
                    stream: _firestoreService.getUserGroups(user.uid),
                    emptyListMessage: 'No groups yet. Create or join one!',
                    itemBuilder: (group) {
                      final isOwner = group.ownerId == user.uid;
                      return Card(
                        child: ListTile(
                          title: Text(group.name),
                           trailing: isOwner 
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () {
                                      context.push('/group/${group.id}/edit', extra: group);
                                    },
                                    tooltip: 'Edit Group',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _deleteGroup(group.id),
                                    tooltip: 'Delete Group',
                                  ),
                                ],
                              )
                            : null,
                          onTap: () {
                            context.go('/group/${group.id}');
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
    required Widget Function(T item) itemBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onAdd,
              tooltip: 'Create new',
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<T>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
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
              );
            }
            final items = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return itemBuilder(items[index]);
              },
            );
          },
        ),
      ],
    );
  }
}
