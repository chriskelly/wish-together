import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/models/group.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:myapp/models/user.dart';

class GroupDetailsPage extends StatelessWidget {
  final String groupId;

  const GroupDetailsPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<Group?>(
          stream: firestoreService.getGroup(groupId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text('Group Details');
            }
            return Text(snapshot.data!.name);
          },
        ),
        actions: [
          StreamBuilder<Group?>(
            stream: firestoreService.getGroup(groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const SizedBox.shrink();
              }
              final group = snapshot.data!;
              if (group.ownerId == currentUser?.uid) {
                return IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () {
                    final invitationLink = '${Uri.base.origin}/#/join?group=$groupId';
                    Clipboard.setData(ClipboardData(text: invitationLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation link copied!')),
                    );
                  },
                  tooltip: 'Copy Invitation Link',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: StreamBuilder<Group?>(
        stream: firestoreService.getGroup(groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Group not found.'));
          }
          final group = snapshot.data!;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shared Wishlists Section
                  Text('Shared Wishlists', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  StreamBuilder<List<Wishlist>>(
                    stream: firestoreService.getSharedWishlistsForGroup(groupId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'No wishlists have been shared with this group yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      final wishlists = snapshot.data!;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: wishlists.length,
                        itemBuilder: (context, index) {
                          final wishlist = wishlists[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(wishlist.name),
                              onTap: () => context.go('/wishlist/${wishlist.id}'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Members Section
                  Text('Members', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  StreamBuilder<List<AppUser>>(
                    stream: firestoreService.getGroupMembers(groupId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final members = snapshot.data!;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(member.displayName ?? 'No Name'),
                              subtitle: Text(member.id == group.ownerId ? 'Owner' : 'Member'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  // Leave Group Button
                  if (group.ownerId != currentUser?.uid)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20.0),
                      child: Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.exit_to_app, color: Colors.red),
                          label: const Text('Leave Group', style: TextStyle(color: Colors.red)),
                          onPressed: () => _confirmLeaveGroup(context, firestoreService, groupId, currentUser!.uid)
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmLeaveGroup(BuildContext context, FirestoreService firestoreService, String groupId, String userId) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave Group?'),
          content: const Text('Are you sure you want to leave this group?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Leave', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog
                try {
                  await firestoreService.leaveGroup(groupId, userId);
                  if (context.mounted) {
                    context.go('/'); // Navigate to home page after leaving
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You have left the group.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to leave group: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}
