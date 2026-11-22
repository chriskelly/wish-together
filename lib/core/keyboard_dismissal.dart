import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Hides the keyboard when the user swipes down anywhere on a page.
///
/// Flutter has no equivalent of UIKit's interactive keyboard dismissal, so
/// this is a deliberate downward drag past [kTouchSlop] rather than a gesture
/// the keyboard follows. It acts only for touch pointers while the platform
/// reports an on-screen keyboard inset; a floating or hardware keyboard does
/// not report one, so the gesture stays inert there. Raw pointer events keep
/// it out of the gesture arena, so it never consumes a scroll or a control's
/// gesture.
class KeyboardDismissal extends StatefulWidget {
  const KeyboardDismissal({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardDismissal> createState() => _KeyboardDismissalState();
}

class _KeyboardDismissalState extends State<KeyboardDismissal> {
  /// Whether the platform reports an on-screen keyboard.
  bool _keyboardUp = false;

  /// The pointer being followed, so a second touch does not move the origin.
  int? _pointer;
  Offset? _start;

  /// Whether this gesture has already dismissed the keyboard.
  bool _dismissed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  void _onPointerDown(PointerDownEvent event) {
    // A mouse or trackpad drag is not a swipe; a stylus is left to its own
    // gestures too.
    if (_pointer != null || event.kind != PointerDeviceKind.touch) {
      return;
    }
    _pointer = event.pointer;
    _start = event.position;
    _dismissed = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _dismissed || !_keyboardUp) {
      return;
    }
    final start = _start;
    if (start == null) {
      return;
    }
    final delta = event.position - start;
    // Only a mostly vertical downward drag counts. A tap never gets this far,
    // an upward scroll keeps its gesture, and a horizontal swipe stays with
    // its own control.
    if (delta.dy <= kTouchSlop || delta.dy <= delta.dx.abs()) {
      return;
    }
    _dismissed = true;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _endPointer(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _start = null;
    _dismissed = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _endPointer,
      onPointerCancel: _endPointer,
      child: widget.child,
    );
  }
}
