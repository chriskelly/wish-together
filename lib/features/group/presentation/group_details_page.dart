import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/common/widgets/list_item_actions.dart';
import 'package:myapp/common/widgets/stream_list_builder.dart';
import 'package:myapp/features/group/data/group_repository.dart';
import 'package:myapp/features/group/domain/group.dart';
import 'package:myapp/features/wishlist/data/wishlist_repository.dart';
import 'package:myapp/features/wishlist/domain/wishlist.dart';
import 'package:myapp/features/auth/data/user_repository.dart';
import 'package:myapp/features/auth/domain/user.dart';

class GroupDetailsPage extends StatelessWidget {
  final String groupId;

  const GroupDetailsPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final groupRepository = GroupRepository();
    final wishlistRepository = WishlistRepository();
    final userRepository = UserRepository();
    final authUser = auth.FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<Group?>(
          stream: groupRepository.streamOne(groupId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text('Group Details');
            }
            return Text(snapshot.data!.name, style: Theme.of(context).textTheme.headlineSmall);
          },
        ),
        actions: [
          StreamBuilder<Group?>(
            stream: groupRepository.streamOne(groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const SizedBox.shrink();
              }
              final group = snapshot.data!;
              if (group.ownerId == authUser?.uid) {
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
        stream: groupRepository.streamOne(groupId),
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
                  StreamListBuilder<Wishlist>(
                    stream: wishlistRepository.streamWhere(
                      'sharedWithGroups',
                      arrayContains: groupId,
                    ),
                    isScrollable: false,
                    emptyMessage: 'No wishlists have been shared with this group yet.',
                    itemBuilder: (context, wishlist) {
                      final isOwner = wishlist.ownerId == authUser?.uid;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        child: FutureBuilder<User?>(
                          future: userRepository.get(wishlist.ownerId),
                          builder: (context, userSnapshot) {
                            String subtitle = 'Loading...';
                            if (userSnapshot.connectionState ==
                                ConnectionState.done) {
                              if (userSnapshot.hasData &&
                                  userSnapshot.data != null) {
                                subtitle = isOwner
                                    ? 'Owned by you'
                                    : 'Owned by ${userSnapshot.data!.displayName}';
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
                                  ? ListItemActions(
                                      onDelete: () => _confirmRemoveWishlist(
                                        context,
                                        wishlistRepository,
                                        group.id!,
                                        wishlist,
                                      ),
                                      deleteIcon: Icons.remove_circle_outline,
                                      deleteTooltip: 'Remove from group',
                                    )
                                  : null,
                            );
                          },
                        ),
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
                  StreamListBuilder<User>(
                    stream: userRepository.streamUsersFromIds(group.members),
                    isScrollable: false,
                    emptyMessage: 'This group has no members.',
                    itemBuilder: (context, member) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6.0,
                          horizontal: 8.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              member.displayName ?? 'No Name',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              member.id == group.ownerId ? 'Owner' : 'Member',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Leave Group Button
                  if (group.ownerId != authUser?.uid)
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
                            groupRepository,
                            group.id!,
                            authUser!.uid,
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
        stream: groupRepository.streamOne(groupId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null || authUser == null) {
            return const SizedBox.shrink();
          }
          final group = snapshot.data!;
          if (group.members.contains(authUser.uid)) {
            return FloatingActionButton.extended(
              onPressed: () => _showShareWishlistDialog(
                context,
                wishlistRepository,
                authUser.uid,
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
    WishlistRepository wishlistRepository,
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
                  final updatedWishlist = wishlist.copyWith(
                    sharedWithGroups: List.from(wishlist.sharedWithGroups)
                      ..remove(groupId),
                  );
                  await wishlistRepository.update(
                    updatedWishlist.id!,
                    updatedWishlist,
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
    WishlistRepository wishlistRepository,
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
              stream: wishlistRepository.streamWhere(
                'ownerId',
                isEqualTo: userId,
              ),
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
                    'All of your wishlists are already shared with this group.',
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
                          final updatedWishlist = wishlist.copyWith(
                            sharedWithGroups: List.from(
                              wishlist.sharedWithGroups,
                            )..add(groupId),
                          );
                          await wishlistRepository.update(
                            updatedWishlist.id!,
                            updatedWishlist,
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
    GroupRepository groupRepository,
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
                  await groupRepository.leaveGroup(groupId, userId);
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
