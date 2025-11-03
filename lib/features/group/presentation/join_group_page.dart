import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
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
  bool _isJoining = false;

  Future<void> _joinGroup() async {
    final currentUser = Provider.of<auth.User?>(context, listen: false);
    if (currentUser == null) return;

    setState(() {
      _isJoining = true;
    });

    try {
      await _groupRepository.joinGroup(widget.groupId, currentUser.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined the group!')),
        );
        // Go to the group details page after joining
        context.goNamed(
          GroupDetailsPage.routeName,
          pathParameters: {'id': widget.groupId},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error joining group: $e')));
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  void _declineInvitation() {
    // Simply navigate back to the home page
    context.go(HomePage.route);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<auth.User?>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Group Invitation',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: FutureBuilder<Group?>(
        future: _groupRepository.get(widget.groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(
              child: Text('This invitation is no longer valid.'),
            );
          }

          final group = snapshot.data!;

          // Check if user is already a member
          if (currentUser != null &&
              group.members.contains(currentUser.uid)) {
            return Center(
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
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 40,
                    child: Icon(Icons.group, size: 40),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'You\'ve been invited to join',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 40),
                  _isJoining
                      ? const CircularProgressIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _declineInvitation,
                              child: const Text('Decline'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.group_add_outlined),
                              onPressed: _joinGroup,
                              label: const Text('Join Group'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
