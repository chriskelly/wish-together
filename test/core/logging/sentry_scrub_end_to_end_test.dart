import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/sentry_policy.dart';

const String phone = '555-123-4567';
const String deviceName = 'Chris iPhone';
const String typedName = 'Grace Hopper';
const String dsn = 'https://public@example.invalid/1';

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
    final options = SentryOptions(dsn: dsn)
      ..tracesSampleRate = 0
      ..beforeSend = scrubEvent
      ..beforeBreadcrumb = scrubBreadcrumb;
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

    await client.captureException(
      Exception('call me on $phone'),
      stackTrace: StackTrace.current,
      scope: scope,
    );

    final envelope = transport.envelope;
    expect(envelope, isNotNull);
    final eventItem = envelope!.items.singleWhere(
      (item) => item.header.type == 'event',
    );
    final text = utf8.decode(await eventItem.dataFactory());

    expect(text, isNot(contains(phone)), reason: 'exception message leaked');
    expect(text, isNot(contains(deviceName)), reason: 'device name leaked');
    expect(text, isNot(contains(typedName)), reason: 'typed name leaked');
    expect(text, contains('17.2'), reason: 'OS version is allowed');
    expect(text, contains('1.2.3'), reason: 'app version is allowed');
  });
}
