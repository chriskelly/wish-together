import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/app_urls.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/group/application/share_wishlist_with_group_use_case.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_form_page.dart';
import 'package:wishtogether/features/group/presentation/group_member_row.dart';
import 'package:wishtogether/features/group/presentation/group_wishlist_row.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';
import 'package:wishtogether/features/group/presentation/providers/group_details_providers.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class GroupDetailsPage extends ConsumerWidget {
  static const String routeName = 'groupDetails';
  static const String route = '/group/:id';

  final String groupId;

  const GroupDetailsPage({super.key, required this.groupId});

  static String getInvitationLink(String groupId, {String? origin}) {
    final base = origin ?? (kIsWeb ? Uri.base.origin : appOrigin);
    return Uri.parse(base)
        .replace(
          path: JoinGroupPage.route,
          queryParameters: {JoinGroupPage.groupIdParam: groupId},
        )
        .toString();
  }

  /// Bottom space the Share Wishlist button takes from the scroll body: the
  /// button's own height (56 at the Material 3 defaults, and text scaling does
  /// not change it), the margin the Scaffold keeps between it and the body, and
  /// a gap so the last row clears the button instead of touching it. Without it
  /// the last row sits underneath the button and takes its taps.
  static const double _fabReserve = 56 + kFloatingActionButtonMargin + 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    // AsyncValue.value keeps the previous value during an error. The old
    // StreamBuilder cleared data on error, so check the error first.
    if (groupAsync.hasError) {
      return _groupLoadError();
    }
    final group = groupAsync.value;
    if (group == null) {
      return groupAsync.isLoading ? _groupLoading() : _groupLoadError();
    }

    final userId = ref.watch(currentUserIdProvider);
    final isOwner = group.ownerId == userId;
    final sharedAsync = ref.watch(groupSharedWishlistsProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));

    return Scaffold(
      appBar: PrimaryAppBar(
        title: group.name,
        actions: _buildAppBarActions(context, group, isOwner),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + _fabReserve),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sharedWishlistsSection(context, sharedAsync, userId),
            const SizedBox(height: 20),
            _membersSection(context, membersAsync, group.ownerId),
            if (!isOwner && userId != null) _leaveGroupButton(context, ref),
          ],
        ),
      ),
      floatingActionButton: userId == null ? null : _shareWishlistFAB(context),
    );
  }

  Widget _groupLoading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  Widget _groupLoadError() => Scaffold(
    appBar: AppBar(title: const Text('Error')),
    body: const Center(child: Text('Group not found.')),
  );

  List<Widget> _buildAppBarActions(
    BuildContext context,
    Group group,
    bool isOwner,
  ) {
    if (!isOwner) return [];

    return [
      IconButton(
        icon: const Icon(Icons.copy_outlined),
        onPressed: () => _onInvitationCopyPressed(context),
        tooltip: 'Copy Invitation Link',
      ),
      IconButton(
        icon: const Icon(Icons.edit),
        onPressed: () => context.pushNamed(
          GroupFormPage.editRouteName,
          pathParameters: {'id': groupId},
          extra: group,
        ),
        tooltip: 'Edit Group',
      ),
    ];
  }

  void _onInvitationCopyPressed(BuildContext context) {
    final invitationLink = getInvitationLink(groupId);
    Clipboard.setData(ClipboardData(text: invitationLink));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Invitation link copied!')));
  }

  Widget _sharedWishlistsSection(
    BuildContext context,
    AsyncValue<List<Wishlist>> sharedAsync,
    String? userId,
  ) => DataSection(
    title: 'Shared Wishlists',
    onAdd: () => _showShareWishlistDialog(context),
    addTooltip: 'Add new wishlist',
    child: ListContentBuilder<Wishlist>(
      items: sharedAsync.value,
      error: sharedAsync.error,
      entityWidgetBuilder: (context, wishlist) => GroupWishlistRow(
        key: ValueKey(wishlist.id),
        groupId: groupId,
        wishlist: wishlist,
        userId: userId,
      ),
      emptyWidget: const ListEmptyPlaceholder(
        message: 'No wishlists have been shared with this group yet.',
      ),
      isScrollable: false,
    ),
  );

  Widget _membersSection(
    BuildContext context,
    AsyncValue<List<User>> membersAsync,
    String ownerId,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Members', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      ListContentBuilder<User>(
        items: membersAsync.value,
        error: membersAsync.error,
        entityWidgetBuilder: (context, member) => GroupMemberRow(
          key: ValueKey(member.id),
          member: member,
          isOwner: member.id == ownerId,
        ),
        emptyMessage: 'This group has no members.',
        isScrollable: false,
      ),
    ],
  );

  Widget _leaveGroupButton(BuildContext context, WidgetRef ref) {
    final error = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Center(
        child: TextButton.icon(
          icon: Icon(Icons.exit_to_app, color: error),
          label: Text('Leave Group', style: TextStyle(color: error)),
          onPressed: () => _onLeaveGroupButtonPressed(context, ref),
        ),
      ),
    );
  }

  Future<void> _onLeaveGroupButtonPressed(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final navigator = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the dialog: reading `ref` after the await would throw if
    // the page left while the confirmation was open.
    final leaveGroup = ref.read(leaveGroupUseCaseProvider);
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Leave Group?',
      content: 'Are you sure you want to leave this group?',
      confirmText: 'Leave',
    );
    if (confirmed != true) return;

    try {
      await leaveGroup.execute(groupId);
      navigator.go(HomePage.route);
      messenger.showSnackBar(
        const SnackBar(content: Text('You have left the group.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }

  Widget _shareWishlistFAB(BuildContext context) =>
      FloatingActionButton.extended(
        onPressed: () => _showShareWishlistDialog(context),
        label: const Text('Share Wishlist'),
        icon: const Icon(Icons.add),
      );

  Future<void> _showShareWishlistDialog(BuildContext pageContext) => showDialog(
    context: pageContext,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Share a Wishlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Consumer(
          builder: (context, ref, child) {
            // An error shows the same copy as an empty list; AsyncValue keeps
            // the previous value on error, so it must not fall through to it.
            final wishlistsAsync = ref.watch(myWishlistsProvider);
            final wishlists = wishlistsAsync.hasError
                ? const <Wishlist>[]
                : wishlistsAsync.value;
            if (wishlists == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (wishlists.isEmpty) {
              return const Text('You have no wishlists to share.');
            }
            final shareable = wishlists
                .where(
                  (wishlist) => !wishlist.sharedWithGroups.contains(groupId),
                )
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
                    // Read the command before the pop, so the tap never uses
                    // the dialog's ref after it is disposed.
                    final share = ref.read(
                      shareWishlistWithGroupUseCaseProvider,
                    );
                    Navigator.of(dialogContext).pop();
                    _shareWishlist(pageContext, share, wishlist);
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

  Future<void> _shareWishlist(
    BuildContext context,
    ShareWishlistWithGroupUseCase share,
    Wishlist wishlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Sharing "${wishlist.name}" with the group.')),
    );
    try {
      await share.execute(wishlist.id!, groupId);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to share wishlist: $e')),
      );
    }
  }
}
