import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/models/group.dart';
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
    return StreamBuilder<User?>(
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

  Widget _buildLoggedInView(BuildContext context, User user) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
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
              Text(
                'Welcome!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
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
                      onTap: () {
                        // TODO: Navigate to wishlist details page
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
                  // TODO: Navigate to a "Create Group" page
                },
                stream: _firestoreService.getUserGroups(user.uid),
                emptyListMessage: 'No groups yet. Create or join one!',
                itemBuilder: (group) {
                  return Card(
                    child: ListTile(
                      title: Text(group.name),
                      onTap: () {
                        // TODO: Navigate to group details page
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
