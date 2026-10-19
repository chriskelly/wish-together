import 'dart:async';

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
    this.updateTimeout = const Duration(seconds: 10),
  });

  /// The message from Remote Config (or the hard-coded fallback).
  final String message;

  /// Opens the store listing and reports whether it opened.
  ///
  /// Null is defensive: the gate never blocks without a usable URL, so a
  /// reachable screen always has this action.
  final Future<bool> Function()? onUpdate;

  /// Re-runs the gate and reports whether the app may start. Null hides the
  /// retry.
  ///
  /// The callback must be self-bounding; production wraps the service's
  /// 5-second total check timeout.
  final Future<bool> Function()? onCheckAgain;

  /// Maximum time to wait for the store action, so a hung launcher cannot
  /// disable both actions forever. A late open is still possible; this only
  /// bounds how long the screen waits before offering a manual path.
  final Duration updateTimeout;

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

enum _Action { idle, updating, checking }

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  _Action _action = _Action.idle;
  String? _feedback;
  late final AppLifecycleListener _lifecycle;

  bool get _isBusy => _action != _Action.idle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // Returning from the App Store is the expected post-update moment, so
      // re-check automatically instead of leaving the user on a stale screen.
      onResume: () => unawaited(_handleCheckAgain()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<bool> Function() action, {
    required _Action kind,
    required String logLabel,
    required String failureFeedback,
  }) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _action = kind;
      _feedback = null;
    });

    var succeeded = false;
    try {
      succeeded = await action();
    } catch (error) {
      debugPrint('App update gate: $logLabel failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _action = _Action.idle;
          if (!succeeded) {
            _feedback = failureFeedback;
          }
        });
      }
    }
  }

  Future<void> _handleUpdate() {
    final onUpdate = widget.onUpdate;
    if (onUpdate == null) {
      return Future.value();
    }
    return _run(
      () => onUpdate().timeout(widget.updateTimeout),
      kind: _Action.updating,
      logLabel: 'update action',
      failureFeedback:
          "Couldn't open the App Store. Please open it manually and update "
          'WishTogether.',
    );
  }

  Future<void> _handleCheckAgain() {
    final onCheckAgain = widget.onCheckAgain;
    if (onCheckAgain == null) {
      return Future.value();
    }
    return _run(
      onCheckAgain,
      kind: _Action.checking,
      logLabel: 'retry',
      failureFeedback: 'Still not available. Try again later.',
    );
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
                      child: Text(
                        _action == _Action.updating ? 'Opening…' : 'Update now',
                      ),
                    ),
                  ),
                  if (widget.onCheckAgain != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isBusy ? null : _handleCheckAgain,
                      child: Text(
                        _action == _Action.checking
                            ? 'Checking…'
                            : 'Check again',
                      ),
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
