import 'package:flutter/material.dart';

/// Runs one page command and shows its success or classified failure copy.
///
/// A command that did not run (because another page action holds the guard)
/// shows nothing. A captured [messenger] keeps the copy alive after the widget
/// that started the action unmounts.
Future<void> runItemAction(
  BuildContext context,
  Future<bool> Function() action, {
  required String success,
  required String Function(Object error) failure,
  void Function(Object error, StackTrace stackTrace)? onError,
  ScaffoldMessengerState? messenger,
}) async {
  try {
    final ran = await action();
    if (!ran || (messenger == null && !context.mounted)) {
      return;
    }
    showItemSnackBar(context, success, messenger: messenger);
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    if (messenger == null && !context.mounted) {
      return;
    }
    showItemSnackBar(context, failure(error), messenger: messenger);
  }
}

/// Shows [message] through [messenger] when one was captured, otherwise
/// through the context's messenger while the context is still mounted.
void showItemSnackBar(
  BuildContext context,
  String message, {
  ScaffoldMessengerState? messenger,
}) {
  if (messenger != null) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
