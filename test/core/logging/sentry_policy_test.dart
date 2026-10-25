import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/log_record.dart';
import 'package:wishtogether/core/logging/sentry_policy.dart';
import 'package:wishtogether/core/logging/session_context.dart';
import 'package:wishtogether/core/logging/redaction.dart';

import 'recording_sink.dart';

const String route = '/wishlist/:id';
const String userRef = '0123456789ab';
const String deniedCode = 'permission-denied';

SessionContext session({String? withUserRef = userRef}) =>
    testSession.withRoute(route).withUserRef(withUserRef);

LogRecord recordFor(AppEvent event, {SessionContext? on}) =>
    LogRecord(event: event, session: on ?? session());

const AuthStateEvent signedOut = AuthStateEvent(outcome: AuthOutcome.signedOut);
const AuthStateEvent failedPhone = AuthStateEvent(
  outcome: AuthOutcome.phone,
  code: deniedCode,
);
const FirestoreErrorEvent firestoreError = FirestoreErrorEvent(
  op: FirestoreOp.list,
  collection: 'items',
  code: deniedCode,
);
const ErrorEvent errorEvent = ErrorEvent(
  runtimeTypeName: 'StateError',
  code: deniedCode,
  route: route,
);
const RouteChangedEvent routeChanged = RouteChangedEvent(route: route);
const UpdateGateEvent failedGate = UpdateGateEvent(
  result: UpdateGateResult.failedOpen,
  reason: 'check-failed',
);
const UpdateGateEvent allowedGate = UpdateGateEvent(
  result: UpdateGateResult.allowed,
);

void main() {
  group('sentryLevelFor', () {
    test('maps an error event to error', () {
      expect(sentryLevelFor(recordFor(errorEvent)), SentryLevel.error);
    });

    test('maps a Firestore error to warning', () {
      expect(sentryLevelFor(recordFor(firestoreError)), SentryLevel.warning);
    });

    test('maps a failed auth state to warning', () {
      expect(sentryLevelFor(recordFor(failedPhone)), SentryLevel.warning);
    });

    test('maps a gate that failed open to warning', () {
      expect(sentryLevelFor(recordFor(failedGate)), SentryLevel.warning);
    });

    test('maps a gate that allowed or blocked to info', () {
      expect(sentryLevelFor(recordFor(allowedGate)), SentryLevel.info);
      expect(
        sentryLevelFor(
          recordFor(const UpdateGateEvent(result: UpdateGateResult.blocked)),
        ),
        SentryLevel.info,
      );
    });

    test('maps everything else to info', () {
      expect(sentryLevelFor(recordFor(signedOut)), SentryLevel.info);
      expect(sentryLevelFor(recordFor(routeChanged)), SentryLevel.info);
    });
  });

  group('shouldCapture', () {
    test('captures errors, Firestore errors and failed auth', () {
      expect(shouldCapture(recordFor(errorEvent)), isTrue);
      expect(shouldCapture(recordFor(firestoreError)), isTrue);
      expect(shouldCapture(recordFor(failedPhone)), isTrue);
    });

    test('captures a gate that failed open', () {
      expect(shouldCapture(recordFor(failedGate)), isTrue);
      expect(shouldCapture(recordFor(allowedGate)), isFalse);
    });

    test('leaves plain events as breadcrumbs only', () {
      expect(shouldCapture(recordFor(signedOut)), isFalse);
      expect(shouldCapture(recordFor(routeChanged)), isFalse);
    });
  });

  group('sentryBreadcrumbFor', () {
    test('carries the event name and allowlisted data', () {
      final breadcrumb = sentryBreadcrumbFor(recordFor(firestoreError));

      expect(breadcrumb.category, sentryBreadcrumbCategory);
      expect(breadcrumb.message, 'firestoreError');
      expect(breadcrumb.data, containsPair('collection', 'items'));
      expect(breadcrumb.level, SentryLevel.warning);
      expect(
        breadcrumb.data!.keys.every(logRecordKeys.contains),
        isTrue,
        reason: 'breadcrumb data must stay inside the §4.3 allowlist',
      );
    });

    test('never carries the user reference as a raw uid', () {
      final breadcrumb = sentryBreadcrumbFor(recordFor(routeChanged));

      expect(breadcrumb.data, containsPair('user_ref', userRef));
    });
  });

  group('sentryEventFor', () {
    test('carries the message, level and allowlisted tags', () {
      final event = sentryEventFor(recordFor(errorEvent));

      expect(event.level, SentryLevel.error);
      expect(event.message?.formatted, contains('error'));
      expect(event.tags, containsPair('error_code', deniedCode));
      expect(event.tags, containsPair('error_type', 'StateError'));
      expect(
        event.tags!.keys.every(logRecordKeys.contains),
        isTrue,
        reason: 'event tags must stay inside the §4.3 allowlist',
      );
    });

    test('keeps the message of every event in the vocabulary', () {
      final records = <LogRecord>[
        recordFor(
          SessionStartEvent(
            build: testSession.build,
            platform: testSession.platform,
            route: route,
          ),
        ),
        recordFor(
          SessionEndEvent(
            build: testSession.build,
            platform: testSession.platform,
            route: route,
            clean: true,
          ),
        ),
        recordFor(signedOut),
        recordFor(failedPhone),
        recordFor(firestoreError),
        recordFor(routeChanged),
        recordFor(allowedGate),
        recordFor(failedGate),
        recordFor(const AppCheckEvent(result: 'activated')),
        recordFor(const ClaimActionEvent(phase: ClaimPhase.started)),
        recordFor(errorEvent),
      ];

      for (final record in records) {
        expect(
          scrubEvent(sentryEventFor(record), Hint())?.message,
          isNotNull,
          reason:
              'every AppEvent must build an event whose message survives the '
              'scrubber; a missing event tag would null it on the wire',
        );
      }
    });

    test('builds a deterministic message from the closed vocabulary', () {
      final first = sentryEventFor(recordFor(firestoreError));
      final second = sentryEventFor(recordFor(firestoreError));

      expect(first.message?.formatted, second.message?.formatted);
      expect(first.message?.formatted, contains('items'));
    });
  });

  group('scopeTagsFor', () {
    test('names the six scope tags of §4.5', () {
      expect(scopeTagsFor(session()), <String, String>{
        'support_code': testSession.supportCode,
        'session_id': testSession.sessionId,
        'build': testSession.build,
        'platform': testSession.platform,
        'route': route,
        'user_ref': userRef,
      });
    });

    test('omits user_ref when signed out', () {
      final tags = scopeTagsFor(session(withUserRef: null));

      expect(tags.containsKey('user_ref'), isFalse);
      expect(tags, hasLength(5));
    });
  });

  group('scrubEvent', () {
    test('keeps an event whose tags are all allowlisted', () {
      final event = sentryEventFor(recordFor(errorEvent));

      expect(scrubEvent(event, Hint()), isNotNull);
    });

    test('drops an event carrying a non-allowlisted tag', () {
      final event = SentryEvent(tags: const {'email': 'a@example.com'});

      expect(scrubEvent(event, Hint()), isNull);
    });

    test('drops an event carrying non-allowlisted extra data', () {
      // ignore: deprecated_member_use
      final event = SentryEvent(extra: const {'item_title': 'Bike'});

      expect(scrubEvent(event, Hint()), isNull);
    });

    test('reduces the user to a valid reference', () {
      final event = SentryEvent(
        tags: const {'event': 'error'},
        user: SentryUser(id: userRef, email: 'a@example.com', username: 'jane'),
        request: SentryRequest(url: 'https://example.com/wishlist/abc'),
      );

      final scrubbed = scrubEvent(event, Hint());

      expect(scrubbed, isNotNull);
      expect(scrubbed!.user?.id, userRef);
      expect(scrubbed.user?.email, isNull);
      expect(scrubbed.user?.username, isNull);
      expect(scrubbed.request, isNull);
    });

    test('strips an exception value and keeps its type and frames', () {
      final frames = <SentryStackFrame>[
        SentryStackFrame(fileName: 'lib/main.dart', function: 'main'),
      ];
      final stackTrace = SentryStackTrace(frames: frames);
      final event = SentryEvent(
        tags: const {'event': 'error'},
        exceptions: <SentryException>[
          SentryException(
            type: 'StateError',
            value: 'call me on 555 0100',
            stackTrace: stackTrace,
          ),
        ],
      );

      final scrubbed = scrubEvent(event, Hint());

      expect(scrubbed!.exceptions!.single.value, isNull);
      expect(scrubbed.exceptions!.single.type, 'StateError');
      expect(scrubbed.exceptions!.single.stackTrace, same(stackTrace));
    });

    test('drops the message of an event this app did not build', () {
      final event = SentryEvent(message: SentryMessage('call me on 555 0100'));

      expect(scrubEvent(event, Hint())?.message, isNull);
    });

    test('keeps the message of an event carrying our provenance tag', () {
      final event = SentryEvent(
        tags: const {'event': 'error'},
        message: SentryMessage('error permission-denied'),
      );

      expect(
        scrubEvent(event, Hint())?.message?.formatted,
        'error permission-denied',
      );
    });

    test('drops a user id that is not a derived reference', () {
      final event = SentryEvent(
        tags: const {'event': 'error'},
        user: SentryUser(id: 'raw-uid-123'),
      );

      expect(scrubEvent(event, Hint())?.user, isNull);
    });
  });

  group('scrubBreadcrumb', () {
    test('keeps our own allowlisted breadcrumb', () {
      final breadcrumb = sentryBreadcrumbFor(recordFor(routeChanged));

      expect(scrubBreadcrumb(breadcrumb, Hint()), isNotNull);
    });

    test('drops a breadcrumb from another category', () {
      final breadcrumb = Breadcrumb(
        category: 'http',
        message: 'GET https://example.com/wishlist/abc',
      );

      expect(scrubBreadcrumb(breadcrumb, Hint()), isNull);
    });

    test('drops a breadcrumb carrying a non-allowlisted key', () {
      final breadcrumb = Breadcrumb(
        category: sentryBreadcrumbCategory,
        data: const {'item_title': 'Bike'},
      );

      expect(scrubBreadcrumb(breadcrumb, Hint()), isNull);
    });

    test('passes a null breadcrumb through as null', () {
      expect(scrubBreadcrumb(null, Hint()), isNull);
    });
  });
}
