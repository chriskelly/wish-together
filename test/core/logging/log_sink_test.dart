import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/log_record.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/logging/session_context.dart';

void main() {
  const session = SessionContext(
    sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
    supportCode: 'ABCDEF',
    build: '53',
    platform: 'ios',
    route: '/wishlist/:id',
  );

  late DebugPrintCallback originalDebugPrint;
  late List<String?> lines;

  setUp(() {
    originalDebugPrint = debugPrint;
    lines = <String?>[];
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message);
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  LogRecord record(AppEvent event) => LogRecord(event: event, session: session);
  String output() => lines.join('\n');

  group('ConsoleSink', () {
    test('prints one readable line per record when enabled', () {
      final sink = ConsoleSink(enabled: true);

      sink.add(
        record(
          const FirestoreErrorEvent(
            op: FirestoreOp.get,
            collection: 'items',
            code: 'permission-denied',
          ),
        ),
      );

      expect(output(), contains('AppLog:'));
      expect(output(), contains('firestoreError'));
      expect(output(), contains('collection=items'));
      expect(output(), contains('error_code=permission-denied'));
      expect(output(), contains('route=/wishlist/:id'));
    });

    test('prints nothing when disabled', () {
      final sink = ConsoleSink(enabled: false);

      sink.add(record(const RouteChangedEvent(route: '/')));

      expect(lines, isEmpty);
    });

    test('prints the stack trace of an error record', () {
      final sink = ConsoleSink(enabled: true);
      final stackTrace = StackTrace.fromString('trace-line-marker');

      sink.add(
        LogRecord(
          event: ErrorEvent(
            runtimeTypeName: 'StateError',
            stackTrace: stackTrace,
            route: '/',
          ),
          session: session,
        ),
      );

      expect(output(), contains('trace-line-marker'));
    });

    test('flush completes', () async {
      final sink = ConsoleSink(enabled: true);

      await expectLater(sink.flush(), completes);
    });
  });
}
