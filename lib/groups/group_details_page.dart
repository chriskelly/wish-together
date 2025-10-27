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
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () {
                        final invitationLink =
                            '${Uri.base.origin}/#/join?group=$groupId';
                        Clipboard.setData(ClipboardData(text: invitationLink));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invitation link copied!'),
                          ),
                        );
                      },
                      tooltip: 'Copy Invitation Link',
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        context.push('/group/${group.id}/edit', extra: group);
                      },
                      tooltip: 'Edit Group',
                    ),
                  ],
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
                  Text(
                    'Shared Wishlists',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<List<Wishlist>>(
                    stream: firestoreService.getSharedWishlistsForGroup(
                      groupId,
                    ),
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
                          final isOwner = wishlist.ownerId == currentUser?.uid;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: FutureBuilder<AppUser?>(
                              future: firestoreService.getUser(wishlist.ownerId),
                              builder: (context, userSnapshot) {
                                String subtitle = 'Loading...';
                                if (userSnapshot.connectionState == ConnectionState.done) {
                                  if (userSnapshot.hasData && userSnapshot.data != null) {
                                    subtitle = isOwner ? 'Owned by you' : 'Owned by ${userSnapshot.data!.displayName}';
                                  } else {
                                    subtitle = 'by an unknown user';
                                  }
                                }

                                return ListTile(
                                  title: Text(wishlist.name),
                                  subtitle: Text(subtitle),
                                  onTap: () =>
                                      context.go('/wishlist/${wishlist.id}'),
                                  trailing: isOwner
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _confirmRemoveWishlist(
                                            context,
                                            firestoreService,
                                            group.id,
                                            wishlist,
                                          ),
                                          tooltip: 'Remove from group',
                                        )
                                      : null,
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Members Section
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<List<AppUser>>(
                    stream: firestoreService.getGroupMembers(groupId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final members = snapshot.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: members.map((member) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6.0, horizontal: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  member.displayName ?? 'No Name',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                Text(
                                  member.id == group.ownerId ? 'Owner' : 'Member',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey[600]
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  // Leave Group Button
                  if (group.ownerId != currentUser?.uid)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20.0),
                      child: Center(
                        child: TextButton.icon(
                          icon: const Icon(
                            Icons.exit_to_app,
                            color: Colors.red,
                          ),
                          label: const Text(
                            'Leave Group',
                            style: TextStyle(color: Colors.red),
                          ),
                          onPressed: () => _confirmLeaveGroup(
                            context,
                            firestoreService,
                            group.id,
                            currentUser!.uid,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: StreamBuilder<Group?>(
        stream: firestoreService.getGroup(groupId),
        builder: (context, snapshot) {
          if (!snapshot.hasData ||
              snapshot.data == null ||
              currentUser == null) {
            return const SizedBox.shrink();
          }
          final group = snapshot.data!;
          if (group.members.contains(currentUser.uid)) {
            return FloatingActionButton.extended(
              onPressed: () => _showShareWishlistDialog(
                context,
                firestoreService,
                currentUser.uid,
                groupId,
              ),
              label: const Text('Share Wishlist'),
              icon: const Icon(Icons.add),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _confirmRemoveWishlist(
    BuildContext context,
    FirestoreService firestoreService,
    String groupId,
    Wishlist wishlist,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Wishlist?'),
          content: Text(
            'Are you sure you want to remove "${wishlist.name}" from this group?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog
                try {
                  await firestoreService.unshareWishlistFromGroup(
                    wishlist.id!,
                    groupId,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Wishlist removed from group.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to remove wishlist: $e')),
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

  Future<void> _showShareWishlistDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String userId,
    String groupId,
  ) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Share a Wishlist'),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<Wishlist>>(
              stream: firestoreService.getUserWishlists(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Text('You have no wishlists to share.');
                }
                final allWishlists = snapshot.data!;
                final shareableWishlists = allWishlists
                    .where((w) => !w.sharedWithGroups.contains(groupId))
                    .toList();

                if (shareableWishlists.isEmpty) {
                  return const Text(
                    'All of your wishlists are shared with this group.',
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: shareableWishlists.length,
                  itemBuilder: (context, index) {
                    final wishlist = shareableWishlists[index];
                    return ListTile(
                      title: Text(wishlist.name),
                      onTap: () async {
                        try {
                          await firestoreService.shareWishlistWithGroup(
                            wishlist.id!,
                            groupId,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '"${wishlist.name}" shared with the group.',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to share wishlist: $e'),
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmLeaveGroup(
    BuildContext context,
    FirestoreService firestoreService,
    String groupId,
    String userId,
  ) async {
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
                    context.go('/');
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
