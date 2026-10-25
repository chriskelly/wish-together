import 'package:flutter/foundation.dart';

import 'log_record.dart';

/// A destination for log records.
///
/// Implementations must not throw. `AppLog` still guards every call, because
/// diagnostics must never change the app's behaviour
/// (`app_update_service.dart`'s "fail open" precedent).
abstract class LogSink {
  /// Delivers one record.
  void add(LogRecord record);

  /// Completes once buffered records are delivered, if the sink buffers.
  Future<void> flush();
}

/// Writes one readable line per record through [debugPrint].
///
/// [enabled] is injected instead of reading `kDebugMode` inside the sink, so
/// the debug/release gate is a plain branch that a VM test can drive (the same
/// split as `universalLinkHostsFor({required bool debug})`).
class ConsoleSink implements LogSink {
  ConsoleSink({required this.enabled});

  /// Whether records are printed. The composition root passes `kDebugMode`.
  final bool enabled;

  @override
  void add(LogRecord record) {
    if (!enabled) {
      return;
    }
    final fields = record.toMap();
    final event = fields.remove('event');
    final values = fields.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint('AppLog: $event $values');
    final stackTrace = record.stackTrace;
    if (stackTrace != null) {
      // Printed through debugPrint (not debugPrintStack) so the debug channel
      // stays injectable and the trace is not filtered down to frame lines.
      debugPrint(stackTrace.toString());
    }
  }

  @override
  Future<void> flush() async {}
}
