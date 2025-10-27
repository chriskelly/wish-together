import 'package:flutter/material.dart';
import 'package:myapp/models/group.dart';
import 'package:myapp/models/user.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:go_router/go_router.dart';

class GroupDetailsPage extends StatefulWidget {
  final String groupId;

  const GroupDetailsPage({super.key, required this.groupId});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Group?>(
      stream: _firestoreService.getGroup(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Group not found.')),
          );
        }

        final group = snapshot.data!;

        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: () {
                  // TODO: Implement adding a member
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add member functionality not yet implemented.')),
                  );
                },
                tooltip: 'Add Member',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMembersSection(context, widget.groupId),
                const SizedBox(height: 24),
                _buildSharedWishlistsSection(context, widget.groupId),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMembersSection(BuildContext context, String groupId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Members', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        StreamBuilder<List<AppUser>>(
          stream: _firestoreService.getGroupMembers(groupId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final members = snapshot.data ?? [];
            if (members.isEmpty) {
              return const Text('No members in this group yet.');
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                return Card(
                  child: ListTile(
                    title: Text(member.displayName ?? 'No Name'),
                    leading: const Icon(Icons.person_outline),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSharedWishlistsSection(BuildContext context, String groupId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Shared Wishlists', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        StreamBuilder<List<Wishlist>>(
          stream: _firestoreService.getSharedWishlistsForGroup(groupId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final wishlists = snapshot.data ?? [];
            if (wishlists.isEmpty) {
              return const Text('No wishlists have been shared with this group yet.');
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: wishlists.length,
              itemBuilder: (context, index) {
                final wishlist = wishlists[index];
                return Card(
                  child: ListTile(
                    title: Text(wishlist.name),
                    onTap: () => context.go('/wishlist/${wishlist.id}'),
                    leading: const Icon(Icons.cake_outlined),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
