import 'package:flutter/material.dart';

/// A small loading indicator designed to be used inside buttons.
/// Used to show loading state while a button action is in progress.
class ButtonLoadingIndicator extends StatelessWidget {
  const ButtonLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        // The indicator is shown exactly while the button is disabled, so the
        // fill behind it is Material's muted disabled fill. `onPrimary` (cream
        // in light) disappears there; the primary colour stays legible.
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
