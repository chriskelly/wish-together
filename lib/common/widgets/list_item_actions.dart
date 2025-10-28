import 'package:flutter/material.dart';

class ListItemActions extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? editTooltip;
  final String? deleteTooltip;
  final IconData deleteIcon;

  const ListItemActions({
    super.key,
    this.onEdit,
    this.onDelete,
    this.editTooltip,
    this.deleteTooltip,
    this.deleteIcon = Icons.delete_outline,
  });

  @override
  Widget build(BuildContext context) {
    // If no actions are provided, don't render anything.
    if (onEdit == null && onDelete == null) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min, // Keep the row compact
      children: [
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
            tooltip: editTooltip ?? 'Edit',
          ),
        if (onDelete != null)
          IconButton(
            icon: Icon(deleteIcon, color: Colors.redAccent),
            onPressed: onDelete,
            tooltip: deleteTooltip ?? 'Delete',
          ),
      ],
    );
  }
}
