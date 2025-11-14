import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
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

  static String getInvitationLink(String groupId) {
    // Use a hardcoded origin for tests and Uri.base for web
    final origin = kIsWeb ? Uri.base.origin : 'http://localhost';
    return '$origin/#/join?group=$groupId';
  }

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final GroupRepository _groupRepository = getIt<GroupRepository>();
  final WishlistRepository _wishlistRepository = getIt<WishlistRepository>();
  final UserRepository _userRepository = getIt<UserRepository>();
  late final String _authUserId;

  @override
  void initState() {
    super.initState();
    _authUserId = getIt<AuthService>().currentUserId!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Group?>(
      stream: _groupRepository.streamOne(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _groupLoading();
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return _groupLoadError();
        }

        final group = snapshot.data!;
        final isOwner = group.ownerId == _authUserId;

        return Scaffold(
          appBar: _buildAppBar(group, isOwner),
          body: _buildGroupDetails(group, isOwner),
          floatingActionButton: _shareWishlistFAB(group),
        );
      },
    );
  }

  Scaffold _groupLoading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  Scaffold _groupLoadError() => Scaffold(
    appBar: AppBar(title: const Text('Error')),
    body: const Center(child: Text('Group not found.')),
  );

  AppBar _buildAppBar(Group group, bool isOwner) {
    return AppBar(
      title: Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
      actions: _buildAppBarActions(group, isOwner),
    );
  }

  List<Widget> _buildAppBarActions(Group group, bool isOwner) {
    if (!isOwner) return [];

    return [
      IconButton(
        icon: const Icon(Icons.copy_outlined),
        onPressed: () => _onInvitationCopyPressed(group.id!),
        tooltip: 'Copy Invitation Link',
      ),
      IconButton(
        icon: const Icon(Icons.edit),
        onPressed: () => context.pushNamed(
          GroupFormPage.editRouteName,
          pathParameters: {'id': group.id!},
          extra: group,
        ),
        tooltip: 'Edit Group',
      ),
    ];
  }

  void _onInvitationCopyPressed(String groupId) {
    final invitationLink = GroupDetailsPage.getInvitationLink(groupId);
    Clipboard.setData(ClipboardData(text: invitationLink));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invitation link copied!')));
  }

  Widget _buildGroupDetails(Group group, bool isOwner) => SingleChildScrollView(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sharedWishlistsSection(context, group.id!),
        const SizedBox(height: 20),
        _membersSection(group),
        if (!isOwner) _leaveGroupButton(group.id!, _authUserId),
      ],
    ),
  );

  Widget _sharedWishlistsSection(BuildContext context, String groupId) {
    return DataSectionBuilder<Wishlist>(
      title: 'Shared Wishlists',
      onAdd: () => _showShareWishlistDialog(context, _authUserId, groupId),
      stream: _wishlistRepository.streamWhere(
        'sharedWithGroups',
        arrayContains: groupId,
      ),
      emptyListMessage: 'No wishlists have been shared with this group yet.',
      entityWidgetBuilder: _wishlistWidgetBuilder(groupId),
    );
  }

  EntityWidgetBuilder<Wishlist> _wishlistWidgetBuilder(String groupId) =>
      (context, wishlist) {
        final isOwner = wishlist.ownerId == _authUserId;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: FutureBuilder<User?>(
            future: _userRepository.get(wishlist.ownerId),
            builder: (context, userSnapshot) {
              String subtitle = _wishlistTileSubtitle(userSnapshot, isOwner);
              return ListTile(
                title: Text(wishlist.name),
                subtitle: Text(subtitle),
                onTap: () => context.pushNamed(
                  WishlistDetailsPage.routeName,
                  pathParameters: {'id': wishlist.id!},
                ),
                trailing: isOwner
                    ? ListItemActions(
                        onDelete: () =>
                            _confirmRemoveWishlist(context, groupId, wishlist),
                        deleteIcon: Icons.remove_circle_outline,
                        deleteTooltip: 'Remove from group',
                      )
                    : null,
              );
            },
          ),
        );
      };

  String _wishlistTileSubtitle(
    AsyncSnapshot<User?> userSnapshot,
    bool isOwner,
  ) {
    if (userSnapshot.connectionState != ConnectionState.done) {
      return 'Loading...';
    }
    if (userSnapshot.hasData && userSnapshot.data != null) {
      return isOwner
          ? 'Owned by you'
          : 'Owned by ${userSnapshot.data!.displayName}';
    }
    return 'by an unknown user';
  }

  Future<void> _confirmRemoveWishlist(
    BuildContext context,
    String groupId,
    Wishlist wishlist,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bool? confirmed = await _showRemoveWishlistDialog(context, wishlist);
    if (confirmed != true) return;
    try {
      await _wishlistRepository.removeWishlistFromGroup(wishlist.id!, groupId);
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Wishlist removed from group.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to remove wishlist: $e')),
      );
    }
  }

  Future<bool?> _showRemoveWishlistDialog(
    BuildContext context,
    Wishlist wishlist,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove Wishlist?'),
        content: Text(
          'Are you sure you want to remove "${wishlist.name}" from this group?',
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Widget _membersSection(Group group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Members', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        StreamListBuilder<User>(
          stream: _userRepository.streamUsersFromIds(group.members),
          isScrollable: false,
          emptyMessage: 'This group has no members.',
          entityWidgetBuilder: _userWidgetBuilder(group.ownerId),
        ),
      ],
    );
  }

  EntityWidgetBuilder<User> _userWidgetBuilder(String ownerId) =>
      (context, member) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              member.displayName ?? 'No Name',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            Text(
              member.id == ownerId ? 'Owner' : 'Member',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );

  Widget _leaveGroupButton(String groupId, String userId) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Center(
        child: TextButton.icon(
          icon: const Icon(Icons.exit_to_app, color: Colors.red),
          label: const Text('Leave Group', style: TextStyle(color: Colors.red)),
          onPressed: () => _onLeaveGroupButtonPressed(context, groupId, userId),
        ),
      ),
    );
  }

  Future<void> _onLeaveGroupButtonPressed(
    BuildContext context,
    String groupId,
    String userId,
  ) async {
    final navigator = GoRouter.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bool? confirmed = await _showLeaveGroupDialog(context);
    if (confirmed != true) return;

    try {
      await _groupRepository.leaveGroup(groupId, userId);
      navigator.go(HomePage.route);
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('You have left the group.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }

  Future<bool?> _showLeaveGroupDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  FloatingActionButton _shareWishlistFAB(Group group) =>
      FloatingActionButton.extended(
        onPressed: () =>
            _showShareWishlistDialog(context, _authUserId, group.id!),
        label: const Text('Share Wishlist'),
        icon: const Icon(Icons.add),
      );

  Future<void> _showShareWishlistDialog(
    BuildContext context,
    String userId,
    String groupId,
  ) async => showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Share a Wishlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<List<Wishlist>>(
          stream: _wishlistRepository.streamWhere('ownerId', isEqualTo: userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Text('You have no wishlists to share.');
            }
            final shareable = snapshot.data!
                .where((w) => !w.sharedWithGroups.contains(groupId))
                .toList();

            if (shareable.isEmpty) {
              return const Text(
                'All of your wishlists are already shared with this group.',
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: shareable.length,
              itemBuilder: (context, index) {
                final wishlist = shareable[index];
                return ListTile(
                  title: Text(wishlist.name),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _shareWishlist(wishlist, groupId);
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  Future<void> _shareWishlist(Wishlist wishlist, String groupId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text('Sharing "${wishlist.name}" with the group.')),
    );
    try {
      final updatedWishlist = wishlist.copyWith(
        sharedWithGroups: List.from(wishlist.sharedWithGroups)..add(groupId),
      );
      await _wishlistRepository.update(updatedWishlist.id!, updatedWishlist);
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to share wishlist: $e')),
      );
    }
  }
}
