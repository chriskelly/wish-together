import 'package:flutter/material.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';

class JoinGroupPage extends StatefulWidget {
  static const String routeName = 'joinGroup';
  static const String route = '/join';
  final String groupId;

  const JoinGroupPage({super.key, required this.groupId});

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final _groupRepository = getIt<GroupRepository>();
  final _authService = getIt<AuthService>();
  bool _isJoining = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: FutureBuilder<Group?>(
        future: _groupRepository.get(widget.groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return _buildInvalidInvitation();
          }

          final group = snapshot.data!;
          final currentUser = _authService.currentUser;
          if (currentUser != null && group.members.contains(currentUser.uid)) {
            return _buildAlreadyMemberWidget(group);
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

  Widget _buildAlreadyMemberWidget(Group group) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('You are already a member of ${group.name}.'),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => context.goNamed(
            GroupDetailsPage.routeName,
            pathParameters: {'id': widget.groupId},
          ),
          child: const Text('View Group'),
        ),
      ],
    ),
  );

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
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isJoining = true;
    });

    try {
      await _groupRepository.joinGroup(widget.groupId, currentUser.uid);
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

  void _showErrorSnackbar(Object e) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Error joining group: $e')));
}
