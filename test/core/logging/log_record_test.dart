import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/log_record.dart';
import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/core/logging/session_context.dart';

void main() {
  const session = SessionContext(
    sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
    supportCode: 'ABCDEF',
    build: '53',
    platform: 'ios',
    userRef: '23481502b488',
    route: '/wishlist/:id',
  );
  const signedOut = SessionContext(
    sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
    supportCode: 'ABCDEF',
    build: '53',
    platform: 'ios',
  );

  LogRecord record(AppEvent event) => LogRecord(event: event, session: session);

  group('session identifiers', () {
    test('are carried on every record', () {
      final map = record(const RouteChangedEvent(route: '/')).toMap();

      expect(map['session_id'], session.sessionId);
      expect(map['support_code'], session.supportCode);
      expect(map['user_ref'], session.userRef);
      expect(map['build'], session.build);
      expect(map['platform'], session.platform);
    });

    test('omit user_ref when signed out', () {
      final map = LogRecord(
        event: const RouteChangedEvent(route: '/'),
        session: signedOut,
      ).toMap();

      expect(map.containsKey('user_ref'), isFalse);
    });

    test('redacts a hand-built context route and drops a raw uid', () {
      const unsafe = SessionContext(
        sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
        supportCode: 'ABCDEF',
        build: '53',
        platform: 'ios',
        userRef: 'abc123DEF456ghi789JKL012mno3',
        route: '/wishlist/abc123',
      );

      final map = LogRecord(
        event: const AuthStateEvent(outcome: AuthOutcome.signedOut),
        session: unsafe,
      ).toMap();

      expect(map['route'], '/wishlist/:id');
      expect(map.containsKey('user_ref'), isFalse);
    });
  });

  group('event vocabulary', () {
    test('serialises sessionStart with its launch identity', () {
      final map = record(
        const SessionStartEvent(build: '54', platform: 'web', route: '/join'),
      ).toMap();

      expect(map['event'], 'sessionStart');
      expect(map['build'], '54');
      expect(map['platform'], 'web');
      expect(map['route'], '/join');
    });

    test('serialises sessionEnd with the clean flag', () {
      final map = record(
        const SessionEndEvent(
          build: '53',
          platform: 'ios',
          route: '/',
          clean: false,
        ),
      ).toMap();

      expect(map['event'], 'sessionEnd');
      expect(map['clean'], isFalse);
    });

    test('serialises authState outcome and code', () {
      final map = record(
        const AuthStateEvent(
          outcome: AuthOutcome.phone,
          code: 'invalid-verification-code',
        ),
      ).toMap();

      expect(map['event'], 'authState');
      expect(map['outcome'], 'phone');
      expect(map['error_code'], 'invalid-verification-code');
    });

    test('serialises firestoreError with a masked collection path', () {
      final map = record(
        const FirestoreErrorEvent(
          op: FirestoreOp.claim,
          collection: 'wishlists/abc123/items',
          code: 'permission-denied',
        ),
      ).toMap();

      expect(map['event'], 'firestoreError');
      expect(map['op'], 'claim');
      expect(map['collection'], unknownCollection);
      expect(map['error_code'], 'permission-denied');
    });

    test('serialises routeChanged with the pattern, not the session route', () {
      final map = record(const RouteChangedEvent(route: '/group/abc123'))
          .toMap();

      expect(map['event'], 'routeChanged');
      expect(map['route'], '/group/:id');
    });

    test('serialises updateGate bounds and reason', () {
      final map = record(
        const UpdateGateEvent(
          result: UpdateGateResult.blocked,
          min: 54,
          running: 53,
          reason: 'below-minimum',
        ),
      ).toMap();

      expect(map['event'], 'updateGate');
      expect(map['result'], 'blocked');
      expect(map['min'], 54);
      expect(map['running'], 53);
      expect(map['reason'], 'below-minimum');
    });

    test('omits updateGate bounds that are not known', () {
      final map = record(
        const UpdateGateEvent(result: UpdateGateResult.allowed),
      ).toMap();

      expect(map['result'], 'allowed');
      expect(map.containsKey('min'), isFalse);
      expect(map.containsKey('running'), isFalse);
      expect(map.containsKey('reason'), isFalse);
    });

    test('serialises appCheck result and provider', () {
      final map = record(
        const AppCheckEvent(result: 'success', provider: 'DeviceCheck'),
      ).toMap();

      expect(map['event'], 'appCheck');
      expect(map['result'], 'success');
      expect(map['provider'], 'DeviceCheck');
    });

    test('serialises claimAction phase and code', () {
      final map = record(
        const ClaimActionEvent(
          phase: ClaimPhase.denied,
          code: 'permission-denied',
        ),
      ).toMap();

      expect(map['event'], 'claimAction');
      expect(map['phase'], 'denied');
      expect(map['error_code'], 'permission-denied');
    });

    test('serialises an error with type, code and route', () {
      final map = record(
        ErrorEvent(
          runtimeTypeName: 'FirebaseAuthException',
          code: 'invalid-verification-code',
          stackTrace: StackTrace.current,
          route: '/login/abc123',
        ),
      ).toMap();

      expect(map['event'], 'error');
      expect(map['error_type'], 'FirebaseAuthException');
      expect(map['error_code'], 'invalid-verification-code');
      expect(map['route'], '/login/:id');
    });

    test('drops a code that is not shaped like one', () {
      final map = record(
        const AuthStateEvent(
          outcome: AuthOutcome.signedOut,
          code: 'Verification failed for Jane Doe',
        ),
      ).toMap();

      expect(map['outcome'], 'signedOut');
      expect(map.containsKey('error_code'), isFalse);
    });

    test('uses only allowlisted keys for every event', () {
      final events = <AppEvent>[
        const SessionStartEvent(build: '54', platform: 'web', route: '/'),
        const SessionEndEvent(
          build: '53',
          platform: 'ios',
          route: '/',
          clean: true,
        ),
        const AuthStateEvent(outcome: AuthOutcome.google),
        const FirestoreErrorEvent(op: FirestoreOp.write, collection: 'items'),
        const RouteChangedEvent(route: '/'),
        const UpdateGateEvent(result: UpdateGateResult.failedOpen),
        const AppCheckEvent(result: 'failed'),
        const ClaimActionEvent(phase: ClaimPhase.started),
        ErrorEvent(
          runtimeTypeName: 'StateError',
          stackTrace: StackTrace.current,
          route: '/',
        ),
      ];

      for (final event in events) {
        final keys = record(event).toMap().keys;

        expect(
          keys.where((key) => !logRecordKeys.contains(key)),
          isEmpty,
          reason: 'non-allowlisted key on ${event.runtimeType}',
        );
      }
    });

    test(
      'keeps clean only on sessionEnd and the bounds only on updateGate',
      () {
        const sessionEnd = SessionEndEvent(
          build: '53',
          platform: 'ios',
          route: '/',
          clean: true,
        );
        const updateGate = UpdateGateEvent(
          result: UpdateGateResult.blocked,
          min: 54,
          running: 53,
          reason: 'below-minimum',
        );
        final otherEvents = <AppEvent>[
          const SessionStartEvent(build: '53', platform: 'ios', route: '/'),
          const AuthStateEvent(outcome: AuthOutcome.signedOut),
          const FirestoreErrorEvent(op: FirestoreOp.get, collection: 'items'),
          const RouteChangedEvent(route: '/'),
          const AppCheckEvent(result: 'success'),
          const ClaimActionEvent(phase: ClaimPhase.started),
          ErrorEvent(
            runtimeTypeName: 'StateError',
            stackTrace: StackTrace.current,
            route: '/',
          ),
        ];

        final endMap = record(sessionEnd).toMap();
        final gateMap = record(updateGate).toMap();

        expect(endMap['clean'], isTrue);
        expect(endMap.containsKey('min'), isFalse);
        expect(gateMap['min'], 54);
        expect(gateMap.containsKey('clean'), isFalse);

        for (final event in otherEvents) {
          final map = record(event).toMap();
          for (final key in <String>['clean', 'min', 'running', 'reason']) {
            expect(
              map.containsKey(key),
              isFalse,
              reason: '$key on ${event.runtimeType}',
            );
          }
        }
      },
    );
  });

  group('stackTrace', () {
    test('is exposed for an error record, outside the serialised map', () {
      final stackTrace = StackTrace.fromString('trace-line-marker');
      final record = LogRecord(
        event: ErrorEvent(
          runtimeTypeName: 'StateError',
          stackTrace: stackTrace,
          route: '/',
        ),
        session: session,
      );

      expect(record.stackTrace, same(stackTrace));
      expect(record.toMap().containsKey('stack'), isFalse);
    });

    test('is absent for any other event', () {
      final record = LogRecord(
        event: const RouteChangedEvent(route: '/'),
        session: session,
      );

      expect(record.stackTrace, isNull);
    });
  });

  test('every event name in the vocabulary is registered', () {
    final events = <AppEvent>[
      const SessionStartEvent(build: '57', platform: 'ios', route: '/'),
      const SessionEndEvent(
        build: '57',
        platform: 'ios',
        route: '/',
        clean: true,
      ),
      const AuthStateEvent(outcome: AuthOutcome.signedOut),
      const FirestoreErrorEvent(op: FirestoreOp.get, collection: 'items'),
      const RouteChangedEvent(route: '/'),
      const UpdateGateEvent(result: UpdateGateResult.allowed),
      const AppCheckEvent(result: 'activated'),
      const ClaimActionEvent(phase: ClaimPhase.started),
      const ErrorEvent(runtimeTypeName: 'StateError', route: '/'),
    ];

    expect(
      events.map(eventNameFor).toSet(),
      logEventNames,
      reason: 'a new AppEvent subtype must register its name in logEventNames',
    );
  });
}
