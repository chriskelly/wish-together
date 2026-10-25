import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_record.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/logging/session_context.dart';

class RecordingSink implements LogSink {
  final List<LogRecord> records = <LogRecord>[];
  int flushCount = 0;
  bool throwOnAdd = false;
  bool throwOnFlush = false;

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

class CodedError {
  String get code => 'unavailable';
}

class ThrowingToString {
  @override
  String toString() => throw StateError('toString failed');
}

/// Pins that a secret never appears in any serialised value.
void expectNoValueContains(Map<String, Object?> map, String needle) {
  expect(
    map.values.map((value) => '$value'),
    everyElement(isNot(contains(needle))),
  );
}

void main() {
  const session = SessionContext(
    sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
    supportCode: 'ABCDEF',
    build: '53',
    platform: 'ios',
  );
  const uid = 'abc123DEF456ghi789JKL012mno3';

  AppLog logWith(List<LogSink> sinks) => AppLog(session: session, sinks: sinks);

  group('event', () {
    test('delivers each event to every sink as a record', () {
      final first = RecordingSink();
      final second = RecordingSink();
      final log = logWith(<LogSink>[first, second]);

      log.event(const AuthStateEvent(outcome: AuthOutcome.phone));

      expect(first.records.single.event, isA<AuthStateEvent>());
      expect(second.records.single.event, isA<AuthStateEvent>());
    });

    test('carries the session snapshot that was current at emit time', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.event(const AuthStateEvent(outcome: AuthOutcome.signedOut));
      log.setUserRef(uid);
      log.event(const AuthStateEvent(outcome: AuthOutcome.google));

      expect(sink.records.first.toMap().containsKey('user_ref'), isFalse);
      expect(sink.records.last.toMap()['user_ref'], userRefForUid(uid));
    });
  });

  group('error', () {
    test('keeps the runtime type, code and stack but no message text', () {
      const message = 'verification failed for 555-1234';
      final stackTrace = StackTrace.fromString('trace-line-marker');
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.error(StateError(message), stackTrace, code: 'permission-denied');

      final record = sink.records.single;
      final map = record.toMap();

      expect(map['error_type'], 'StateError');
      expect(map['error_code'], 'permission-denied');
      expect(map['route'], session.route);
      expect(record.stackTrace, same(stackTrace));
      expectNoValueContains(map, message);
    });

    test('never calls toString on the thrown object', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      expect(
        () => log.error(ThrowingToString(), StackTrace.current),
        returnsNormally,
      );
      expect(sink.records.single.toMap()['error_type'], 'ThrowingToString');
    });

    test('maps a String code getter from the error', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.error(CodedError(), StackTrace.current);

      expect(sink.records.single.toMap()['error_code'], 'unavailable');
    });

    test('prefers an explicit code over the mapped one', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.error(CodedError(), StackTrace.current, code: 'permission-denied');

      expect(sink.records.single.toMap()['error_code'], 'permission-denied');
    });

    test(
      'falls back to the mapped code when the explicit one is not a code',
      () {
        final sink = RecordingSink();
        final log = logWith(<LogSink>[sink]);

        log.error(CodedError(), StackTrace.current, code: 'not a code at all');

        expect(sink.records.single.toMap()['error_code'], 'unavailable');
      },
    );

    test('tolerates a null stack trace', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.error(StateError('no stack'), null);

      expect(sink.records.single.stackTrace, isNull);
      expect(sink.records.single.toMap()['error_type'], 'StateError');
    });
  });

  group('setUserRef', () {
    test('stores only the derived reference, never the raw uid', () {
      // A realistic 28-character Firebase uid.
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.setUserRef(uid);
      log.event(const AuthStateEvent(outcome: AuthOutcome.google));

      final map = sink.records.single.toMap();

      expect(log.session.userRef, userRefForUid(uid));
      expect(map['user_ref'], userRefForUid(uid));
      expect(map.containsValue(uid), isFalse);
      expectNoValueContains(map, uid);
    });

    test('clears the reference on sign-out', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.setUserRef(uid);
      log.setUserRef(null);
      log.event(const AuthStateEvent(outcome: AuthOutcome.signedOut));

      expect(log.session.userRef, isNull);
      expect(sink.records.single.toMap().containsKey('user_ref'), isFalse);
    });

    test('treats a blank uid as signed out', () {
      final log = logWith(<LogSink>[RecordingSink()]);

      log.setUserRef(uid);
      log.setUserRef('   ');

      expect(log.session.userRef, isNull);
    });
  });

  group('routeChanged', () {
    test('updates the session and emits the redacted pattern', () {
      final sink = RecordingSink();
      final log = logWith(<LogSink>[sink]);

      log.routeChanged('/wishlist/abc123');

      final event = sink.records.single.event;
      expect(log.session.route, '/wishlist/:id');
      expect(event, isA<RouteChangedEvent>());
      expect((event as RouteChangedEvent).route, '/wishlist/:id');
      expect(sink.records.single.toMap()['route'], '/wishlist/:id');
    });
  });

  group('breadcrumbs', () {
    test('keeps the newest 30 and drops the oldest', () {
      const cap = 30;
      const extra = 5;
      final log = logWith(<LogSink>[RecordingSink()]);

      for (var index = 0; index < cap + extra; index++) {
        log.event(ClaimActionEvent(phase: ClaimPhase.started, code: 'c$index'));
      }

      expect(log.breadcrumbs.length, cap);
      expect(log.breadcrumbs.first.toMap()['error_code'], 'c$extra');
      expect(log.breadcrumbs.last.toMap()['error_code'], 'c${cap + extra - 1}');
    });

    test('does not keep errors as breadcrumbs', () {
      final log = logWith(<LogSink>[RecordingSink()]);

      log.event(const AuthStateEvent(outcome: AuthOutcome.signedOut));
      log.error(StateError('boom'), StackTrace.current);

      expect(log.breadcrumbs.length, 1);
      expect(log.breadcrumbs.single.event, isA<AuthStateEvent>());
    });
  });

  group('fire-and-forget', () {
    test('never throws when a sink throws', () {
      final sink = RecordingSink()..throwOnAdd = true;
      final log = logWith(<LogSink>[sink]);

      expect(
        () => log.event(const AuthStateEvent(outcome: AuthOutcome.signedOut)),
        returnsNormally,
      );
      expect(
        () => log.error(StateError('boom'), StackTrace.current),
        returnsNormally,
      );
    });

    test('flushes every sink even when one fails', () async {
      final failing = RecordingSink()..throwOnFlush = true;
      final healthy = RecordingSink();
      final log = logWith(<LogSink>[failing, healthy]);

      await expectLater(log.flush(), completes);

      expect(failing.flushCount, 1);
      expect(healthy.flushCount, 1);
    });
  });
}
