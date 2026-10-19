import 'package:flutter/material.dart';
import 'package:wishtogether/core/theme.dart';

/// A blocking screen shown when the running build is below the minimum
/// supported build.
///
/// It is mounted as the root of its own [MaterialApp] (see [UpdateRequiredApp]),
/// so no route or in-app action is reachable until the user updates.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({
    super.key,
    required this.message,
    this.onUpdate,
    this.onCheckAgain,
  });

  /// The message from Remote Config (or the hard-coded fallback).
  final String message;

  /// Opens the store listing. Null when no update URL is configured, which
  /// disables the button.
  final VoidCallback? onUpdate;

  /// Re-runs the gate, for the rare case where Remote Config was wrong and has
  /// since been corrected.
  final Future<void> Function()? onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Update required',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onUpdate,
                      child: const Text('Update now'),
                    ),
                  ),
                  if (onCheckAgain != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onCheckAgain,
                      child: const Text('Check again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole app while the update gate is blocking.
class UpdateRequiredApp extends StatelessWidget {
  const UpdateRequiredApp({
    super.key,
    required this.message,
    this.onUpdate,
    this.onCheckAgain,
  });

  final String message;
  final VoidCallback? onUpdate;
  final Future<void> Function()? onCheckAgain;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WishTogether',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: UpdateRequiredPage(
        message: message,
        onUpdate: onUpdate,
        onCheckAgain: onCheckAgain,
      ),
    );
  }
}
