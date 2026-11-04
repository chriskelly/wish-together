import 'package:flutter/material.dart';

/// A reusable confirmation dialog for destructive actions.
///
/// Shows a dialog with a title, content message, Cancel button, and a
/// destructive action button (e.g., Delete, Remove, Leave).
///
/// Returns `true` if the user confirmed the action, `false` if cancelled.
Future<bool?> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  required String confirmText,
  Color? confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      // A default parameter cannot read the theme, so the destructive colour
      // resolves here, where the dialog's context exists.
      final destructive =
          confirmColor ?? Theme.of(dialogContext).colorScheme.error;
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmText, style: TextStyle(color: destructive)),
          ),
        ],
      );
    },
  );
}
