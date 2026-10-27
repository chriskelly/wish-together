import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/log_record.dart';

import 'recording_sink.dart';
import 'recording_transport.dart';

import 'package:wishtogether/core/logging/sentry_sink.dart';
import 'package:wishtogether/core/logging/session_context.dart';

const String homeRoute = '/';
const String wishlistRoute = '/wishlist/:id';
const String userRef = '0123456789ab';
const String itemsCollection = 'items';
const String deniedCode = 'permission-denied';

SessionContext session({String route = homeRoute, String? ref = userRef}) =>
    testSession.withRoute(route).withUserRef(ref);

class ThrowingTransport implements SentryTransport {
  @override
  void addBreadcrumb(Breadcrumb breadcrumb) => throw StateError('boom');

  @override
  void applyScope(SessionContext session) => throw StateError('boom');

  @override
  void captureEvent(SentryEvent event, {StackTrace? stackTrace}) =>
      throw StateError('boom');

  @override
  Future<void> flush() async => throw StateError('boom');
}

void main() {
  group('SentrySink', () {
    test('turns a route change into a breadcrumb only', () {
      final transport = RecordingTransport();
      final sink = SentrySink(transport);

      sink.add(
        LogRecord(
          event: const RouteChangedEvent(route: wishlistRoute),
          session: session(route: wishlistRoute),
        ),
      );

      expect(transport.breadcrumbs, hasLength(1));
      expect(transport.breadcrumbs.single.message, 'routeChanged');
      expect(transport.events, isEmpty);
    });

    test('captures an error with its stack as well as a breadcrumb', () {
      final transport = RecordingTransport();
      final sink = SentrySink(transport);
      final stackTrace = StackTrace.current;

      sink.add(
        LogRecord(
          event: ErrorEvent(
            runtimeTypeName: 'StateError',
            code: 'denied',
            stackTrace: stackTrace,
            route: homeRoute,
          ),
          session: session(),
        ),
      );

      expect(transport.breadcrumbs, hasLength(1));
      expect(transport.events, hasLength(1));
      expect(transport.events.single.stackTrace, same(stackTrace));
      expect(transport.events.single.event.level, SentryLevel.error);
    });

    test('captures a Firestore failure as a warning event', () {
      final transport = RecordingTransport();
      final sink = SentrySink(transport);

      sink.add(
        LogRecord(
          event: const FirestoreErrorEvent(
            op: FirestoreOp.list,
            collection: itemsCollection,
            code: deniedCode,
          ),
          session: session(),
        ),
      );

      expect(transport.events, hasLength(1));
      expect(transport.events.single.event.level, SentryLevel.warning);
      expect(
        transport.events.single.event.tags,
        allOf(
          containsPair('collection', itemsCollection),
          // scrubEvent keys message provenance on this tag; without it every
          // captured event would silently lose its message.
          containsPair('event', 'firestoreError'),
        ),
      );
    });

    test('applies the scope once per distinct session', () {
      final transport = RecordingTransport();
      final sink = SentrySink(transport);

      sink.add(
        LogRecord(
          event: const RouteChangedEvent(route: homeRoute),
          session: session(),
        ),
      );
      sink.add(
        LogRecord(
          event: const RouteChangedEvent(route: homeRoute),
          session: session(),
        ),
      );
      sink.add(
        LogRecord(
          event: const RouteChangedEvent(route: wishlistRoute),
          session: session(route: wishlistRoute),
        ),
      );

      expect(transport.scopes, hasLength(2));
      expect(transport.scopes.last.route, wishlistRoute);
    });

    test('reapplies the scope when the user signs out', () {
      final transport = RecordingTransport();
      final sink = SentrySink(transport);

      sink.add(
        LogRecord(
          event: const RouteChangedEvent(route: homeRoute),
          session: session(),
        ),
      );
      sink.add(
        LogRecord(
          event: const AuthStateEvent(outcome: AuthOutcome.signedOut),
          session: session(ref: null),
        ),
      );

      expect(transport.scopes.last.userRef, isNull);
    });

    test('never throws when the transport does', () {
      final sink = SentrySink(ThrowingTransport());

      expect(
        () => sink.add(
          LogRecord(
            event: const RouteChangedEvent(route: homeRoute),
            session: session(),
          ),
        ),
        returnsNormally,
      );
    });

    test('flush delegates to the transport', () async {
      final transport = RecordingTransport();
      final sink = SentrySink(transport);

      await sink.flush();

      expect(transport.flushes, 1);
    });
  });
}
