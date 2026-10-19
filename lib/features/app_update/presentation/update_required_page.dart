import 'package:flutter/material.dart';
import 'package:wishtogether/core/theme.dart';

/// A blocking screen shown when the running build is below the minimum
/// supported build.
///
/// It is mounted as the root of its own [MaterialApp] (see [UpdateRequiredApp]),
/// so no route or in-app action is reachable until the user updates.
class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({
    super.key,
    required this.message,
    this.onUpdate,
    this.onCheckAgain,
  });

  /// The message from Remote Config (or the hard-coded fallback).
  final String message;

  /// Opens the store listing and reports whether it opened. Null when no
  /// usable update URL is configured, which disables the button.
  final Future<bool> Function()? onUpdate;

  /// Re-runs the gate and reports whether the app may start. Null hides the
  /// retry.
  final Future<bool> Function()? onCheckAgain;

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  bool _isUpdating = false;
  bool _isChecking = false;
  String? _feedback;

  bool get _isBusy => _isUpdating || _isChecking;

  Future<void> _handleUpdate() async {
    final onUpdate = widget.onUpdate;
    if (onUpdate == null || _isBusy) {
      return;
    }
    setState(() {
      _isUpdating = true;
      _feedback = null;
    });
    final opened = await onUpdate();
    if (!mounted) {
      return;
    }
    setState(() {
      _isUpdating = false;
      if (!opened) {
        _feedback =
            "Couldn't open the App Store. Please open it manually and update "
            'WishTogether.';
      }
    });
  }

  Future<void> _handleCheckAgain() async {
    final onCheckAgain = widget.onCheckAgain;
    if (onCheckAgain == null || _isBusy) {
      return;
    }
    setState(() {
      _isChecking = true;
      _feedback = null;
    });
    final started = await onCheckAgain();
    if (!mounted) {
      return;
    }
    setState(() {
      _isChecking = false;
      if (!started) {
        _feedback = 'Still not available. Try again later.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    widget.message,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _feedback!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.onUpdate == null || _isBusy
                          ? null
                          : _handleUpdate,
                      child: Text(_isUpdating ? 'Opening…' : 'Update now'),
                    ),
                  ),
                  if (widget.onCheckAgain != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isBusy ? null : _handleCheckAgain,
                      child: Text(_isChecking ? 'Checking…' : 'Check again'),
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
  final Future<bool> Function()? onUpdate;
  final Future<bool> Function()? onCheckAgain;

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
