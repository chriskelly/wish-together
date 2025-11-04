import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';

class GroupDetailsPage extends StatefulWidget {
  static const String routeName = 'groupDetails';
  static const String route = '/group/:id';
  final String groupId;

  const GroupDetailsPage({super.key, required this.groupId});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final GroupRepository _groupRepository = getIt<GroupRepository>();
  final WishlistRepository _wishlistRepository = getIt<WishlistRepository>();
  final UserRepository _userRepository = getIt<UserRepository>();
  late final auth.User? _authUser;

  @override
  void initState() {
    super.initState();
    _authUser = getIt<AuthService>().currentUser;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<Group?>(
          stream: _groupRepository.streamOne(widget.groupId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text('Group Details');
            }
            return Text(
              snapshot.data!.name,
              style: Theme.of(context).textTheme.headlineSmall,
            );
          },
        ),
        actions: [
          StreamBuilder<Group?>(
            stream: _groupRepository.streamOne(widget.groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const SizedBox.shrink();
              }
              final group = snapshot.data!;
              if (group.ownerId == _authUser?.uid) {
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () {
                        final invitationLink =
                            '${Uri.base.origin}/#/join?group=${widget.groupId}';
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
                        context.pushNamed(
                          GroupFormPage.editRouteName,
                          pathParameters: {'id': group.id!},
                          extra: group,
                        );
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
        stream: _groupRepository.streamOne(widget.groupId),
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
                    stream: _wishlistRepository.streamWhere(
                      'sharedWithGroups',
                      arrayContains: widget.groupId,
                    ),
                    isScrollable: false,
                    emptyMessage:
                        'No wishlists have been shared with this group yet.',
                    itemBuilder: (context, wishlist) {
                      final isOwner = wishlist.ownerId == _authUser?.uid;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        child: FutureBuilder<User?>(
                          future: _userRepository.get(wishlist.ownerId),
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
                              onTap: () => context.pushNamed(
                                WishlistDetailsPage.routeName,
                                pathParameters: {'id': wishlist.id!},
                              ),
                              trailing: isOwner
                                  ? ListItemActions(
                                      onDelete: () => _confirmRemoveWishlist(
                                        context,
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
                    stream: _userRepository.streamUsersFromIds(group.members),
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
                  if (group.ownerId != _authUser?.uid)
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
                            group.id!,
                            _authUser!.uid,
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
        stream: _groupRepository.streamOne(widget.groupId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null || _authUser == null) {
            return const SizedBox.shrink();
          }
          final group = snapshot.data!;
          if (group.members.contains(_authUser.uid)) {
            return FloatingActionButton.extended(
              onPressed: () => _showShareWishlistDialog(
                context,
                _authUser.uid,
                widget.groupId,
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
                  await _wishlistRepository.update(
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
              stream: _wishlistRepository.streamWhere(
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
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Sharing "${wishlist.name}" with the group...',
                                ),
                              ),
                            );
                          }
                          final updatedWishlist = wishlist.copyWith(
                            sharedWithGroups: List.from(
                              wishlist.sharedWithGroups,
                            )..add(groupId),
                          );
                          await _wishlistRepository.update(
                            updatedWishlist.id!,
                            updatedWishlist,
                          );
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
                  await _groupRepository.leaveGroup(groupId, userId);
                  if (context.mounted) {
                    context.go(HomePage.route);
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
