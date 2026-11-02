import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/group/application/join_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';

class JoinGroupPage extends StatefulWidget {
  static const String routeName = 'joinGroup';
  static const String route = '/join';
  static const String groupIdParam = 'group';
  final String groupId;

  const JoinGroupPage({super.key, required this.groupId});

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final _groupRepository = getIt<GroupRepository>();
  final _session = getIt<AuthSession>();
  final _joinGroupUseCase = getIt<JoinGroupUseCase>();
  late Future<Group?> _groupFuture;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _groupFuture = _groupRepository.get(widget.groupId);
  }

  @override
  void didUpdateWidget(covariant JoinGroupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The join route is keyed by its path, not its query string, so following a
    // second invite link updates this page in place. The new group id has to be
    // read: the membership decision and the group name come from this document,
    // while the redirect and the join themselves use `widget.groupId`.
    //
    // A rebuild with the same id deliberately does not re-read: the decision
    // has already been made from this document and re-fetching on every rebuild
    // would flash the loading state and could navigate twice.
    if (oldWidget.groupId != widget.groupId) {
      _groupFuture = _groupRepository.get(widget.groupId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: FutureBuilder<Group?>(
        future: _groupFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return _buildInvalidInvitation();
          }

          final group = snapshot.data!;
          final currentUserId = _session.currentUserId;
          if (currentUserId != null && group.members.contains(currentUserId)) {
            return _RedirectToGroup(
              groupId: widget.groupId,
              child: _buildLoadingState(),
            );
          }
          return _buildInvitationContent(group);
        },
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    title: Text(
      'Group Invitation',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );

  Widget _buildLoadingState() =>
      const Center(child: CircularProgressIndicator());

  Widget _buildInvalidInvitation() =>
      const Center(child: Text('This invitation is no longer valid.'));

  Widget _buildInvitationContent(Group group) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _groupAvatar(),
          const SizedBox(height: 20),
          _invitationText(),
          const SizedBox(height: 4),
          _groupNameText(group),
          const SizedBox(height: 40),
          _actionButtons(),
        ],
      ),
    ),
  );

  Widget _groupAvatar() =>
      const CircleAvatar(radius: 40, child: Icon(Icons.group, size: 40));

  Widget _invitationText() => Text(
    'You\'ve been invited to join',
    style: Theme.of(context).textTheme.titleMedium,
  );

  Widget _groupNameText(Group group) => Text(
    group.name,
    style: Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.bold),
  );

  Widget _actionButtons() => _isJoining
      ? const CircularProgressIndicator()
      : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _declineButton(),
            const SizedBox(width: 16),
            _joinButton(),
          ],
        );

  Widget _declineButton() =>
      TextButton(onPressed: _declineInvitation, child: const Text('Decline'));

  Widget _joinButton() => ElevatedButton.icon(
    icon: const Icon(Icons.group_add_outlined),
    onPressed: _joinGroup,
    label: const Text('Join Group'),
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    ),
  );

  Future<void> _joinGroup() async {
    setState(() {
      _isJoining = true;
    });

    try {
      await _joinGroupUseCase.execute(widget.groupId);
      if (mounted) {
        _showSuccessSnackbarAndNavigate();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(e);
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  void _declineInvitation() {
    context.go(HomePage.route);
  }

  void _showSuccessSnackbarAndNavigate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Successfully joined the group!')),
    );
    context.goNamed(
      GroupDetailsPage.routeName,
      pathParameters: {'id': widget.groupId},
    );
  }

  void _showErrorSnackbar(Object e) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error joining group: $e')));
}

/// Sends a viewer who already belongs to the group straight to its details
/// page, instead of stopping on an "already a member" page with a button.
///
/// Navigation cannot run during a build, so it waits one frame. [child] is the
/// loading state, which is what the viewer sees until that frame: no
/// interstitial is ever painted, and the location is replaced, so the invite
/// link is not on the back stack.
///
/// The decision lives here rather than in the router's redirect because this
/// page has already read the group document; the router redirect would have to
/// read it again on every `/join` navigation.
class _RedirectToGroup extends StatefulWidget {
  final String groupId;
  final Widget child;

  const _RedirectToGroup({required this.groupId, required this.child});

  @override
  State<_RedirectToGroup> createState() => _RedirectToGroupState();
}

class _RedirectToGroupState extends State<_RedirectToGroup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A plain `go` pushes a browser history entry, so Back would return to
      // the invite, which would forward again: a Back button that does
      // nothing. Neglecting the report marks the entry replaced, so `/join`
      // never becomes a place the user can return to.
      Router.neglect(
        context,
        () => context.goNamed(
          GroupDetailsPage.routeName,
          pathParameters: {'id': widget.groupId},
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
