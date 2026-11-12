import 'package:flutter/material.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

/// One member of a group: the display name and its role label.
///
/// The page passes the owner flag so the row does not need the group document.
class GroupMemberRow extends StatelessWidget {
  const GroupMemberRow({
    super.key,
    required this.member,
    required this.isOwner,
  });

  final User member;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      child: Row(
        children: [
          // A display name has no length limit. The role label keeps its
          // natural width and the name yields to it, so an unbroken name
          // truncates with an ellipsis instead of a silent hard cut; without
          // the bounded width it would overflow the row and run under the
          // label.
          Expanded(
            child: Text(
              member.displayName ?? 'No Name',
              style: Theme.of(context).textTheme.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOwner ? 'Owner' : 'Member',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
