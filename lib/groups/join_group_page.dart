import 'package:flutter/material.dart';
import 'package:myapp/models/group.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class JoinGroupPage extends StatefulWidget {
  final String groupId;

  const JoinGroupPage({super.key, required this.groupId});

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final _firestoreService = FirestoreService();
  final _currentUser = FirebaseAuth.instance.currentUser;
  bool _isJoining = false;

  Future<void> _joinGroup() async {
    if (_currentUser == null) return;

    setState(() {
      _isJoining = true;
    });

    try {
      await _firestoreService.joinGroup(widget.groupId, _currentUser.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined the group!')),
        );
        // Go to the group details page after joining
        context.go('/group/${widget.groupId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining group: $e')),
        );
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  void _declineInvitation() {
    // Simply navigate back to the home page
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Invitation'),
      ),
      body: FutureBuilder<Group?>(
        future: _firestoreService.getGroupFuture(widget.groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('This invitation is no longer valid.'));
          }

          final group = snapshot.data!;

          // Check if user is already a member
          if (_currentUser != null && group.members.contains(_currentUser.uid)) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('You are already a member of ${group.name}.'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.go('/group/${widget.groupId}'),
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
