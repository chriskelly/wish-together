import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/log_record.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/logging/session_context.dart';

/// A code-shaped error, for seams that read a structured `code`.
class CodedError {
  const CodedError(this.code);

  final String code;
}

/// The claim phases reported through [sink], in order.
List<ClaimPhase> phasesOf(RecordingSink sink) =>
    sink.eventsOf<ClaimActionEvent>().map((event) => event.phase).toList();

/// A fixed launch context for diagnostics tests.
const SessionContext testSession = SessionContext(
  sessionId: '0123456789ABCDEFGHJKMNPQRST',
  supportCode: '012345',
  build: '57',
  platform: 'ios',
);

/// A [LogSink] that keeps every record, for assertions.
///
/// The failure switches are for testing `AppLog`'s "a sink cannot break the
/// caller" contract; they default off.
class RecordingSink implements LogSink {
  final List<LogRecord> records = <LogRecord>[];
  int flushCount = 0;
  bool throwOnAdd = false;
  bool throwOnFlush = false;

  List<AppEvent> get events =>
      records.map((record) => record.event).toList(growable: false);

  Iterable<T> eventsOf<T extends AppEvent>() => events.whereType<T>();

  @override
  void add(LogRecord record) {
    if (throwOnAdd) {
      throw StateError('sink add failed');
    }
    records.add(record);
  }

  @override
  Future<void> flush() async {
    flushCount++;
    if (throwOnFlush) {
      throw StateError('sink flush failed');
    }
  }
}
