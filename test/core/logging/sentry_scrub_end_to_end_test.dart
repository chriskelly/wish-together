import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/sentry_policy.dart';
import 'package:wishtogether/core/logging/sentry_startup.dart';

const String phone = '555-123-4567';
const String documentId = 'aB3dE5fG7hJ9kL1mN3pQ';
const String rawUid = 'kR3nT9xQ2mL7vB5wY8cZ1dF4gH6j';
const String deviceName = 'Chris iPhone';
const String typedName = 'Grace Hopper';
const String dsn = 'https://public@example.invalid/1';

/// The number of leading characters asserted absent as a fragment.
///
/// Whole-token assertions alone would pass if the scrubber started leaking a
/// prefix (for example a truncated id); an eight-character fragment is specific
/// enough that a false match in the surrounding JSON is not plausible, and it
/// contains uppercase letters so it cannot collide with a lowercase hex id.
const int fragmentLength = 8;

class CapturingTransport implements Transport {
  SentryEnvelope? envelope;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    this.envelope = envelope;
    return envelope.header.eventId;
  }
}

void main() {
  test('no free text survives beforeSend into the serialised event', () async {
    // The options come from the real §4.5 configuration, so this test also
    // proves `SentryStartup.configure` installs the policy.
    final options = SentryFlutterOptions();
    SentryStartup.fromEnvironment(
      identity: const BuildIdentity(build: '57', platform: 'web'),
      releaseMode: true,
      dsn: dsn,
    ).configure(options);
    final transport = CapturingTransport();
    options.transport = transport;
    final client = SentryClient(options);
    final scope = Scope(options);
    await scope.addBreadcrumb(
      Breadcrumb(
        category: sentryBreadcrumbCategory,
        message: 'user entered $phone',
        data: const <String, String>{'event': 'error'},
      ),
    );
    await scope.setContexts('device', SentryDevice(name: deviceName));
    await scope.setContexts(
      'os',
      SentryOperatingSystem(name: 'iOS', version: '17.2'),
    );
    await scope.setContexts('app', SentryApp(version: '1.2.3', build: '57'));
    await scope.setContexts('flutter_error_details', <String, String>{
      'information': 'TextEditingValue(text: "$typedName")',
    });
    // Mirrors the web enricher, which defaults `transaction` to the pathname.
    scope.transaction = '/wishlist/$documentId';
    // Mirrors LoadContextsIntegration on a native platform: these two constants
    // are added to every event before beforeSend.
    await scope.setTag('event.origin', 'flutter');
    await scope.setTag('event.environment', 'dart');

    await client.captureException(
      Exception('call me on $phone about $documentId for $rawUid'),
      stackTrace: StackTrace.current,
      scope: scope,
    );

    final envelope = transport.envelope;
    expect(envelope, isNotNull);
    final eventItem = envelope!.items.singleWhere(
      (item) => item.header.type == 'event',
    );
    final text = utf8.decode(await eventItem.dataFactory());

    for (final secret in <String>[phone, documentId, rawUid]) {
      expect(
        text,
        isNot(contains(secret)),
        reason: 'a whole secret must not survive the scrubber',
      );
      expect(
        text,
        isNot(contains(secret.substring(0, fragmentLength))),
        reason: 'no fragment of a secret may survive the scrubber',
      );
    }
    expect(text, isNot(contains(deviceName)), reason: 'device name leaked');
    expect(text, isNot(contains(typedName)), reason: 'typed name leaked');
    expect(
      text,
      isNot(contains('"transaction"')),
      reason: 'the SDK transaction can carry a document id',
    );
    expect(text, contains('17.2'), reason: 'OS version is allowed');
    expect(text, contains('1.2.3'), reason: 'app version is allowed');
  });
}
