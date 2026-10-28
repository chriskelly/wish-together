import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/app_urls.dart';
import 'package:wishtogether/core/deep_links.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';

import 'logging/recording_sink.dart';

void main() {
  late StreamController<Uri> controller;
  late DeepLinkService service;

  setUp(() {
    controller = StreamController<Uri>();
    service = DeepLinkService(
      links: controller.stream,
      allowedHosts: releaseUniversalLinkHosts,
    );
  });

  tearDown(() => controller.close());

  test('queues a link received before startup', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();

    expect(service.takePendingLocation(), '/join?group=one');
  });

  test('the latest link wins before startup', () async {
    controller
      ..add(Uri.parse('https://wishtogether.gift/join?group=one'))
      ..add(Uri.parse('https://wishtogether.gift/group/two'));
    await pumpEventQueue();

    expect(service.takePendingLocation(), '/group/two');
  });

  test('takePendingLocation consumes the queue', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();

    expect(service.takePendingLocation(), '/join?group=one');
    expect(service.takePendingLocation(), isNull);
  });

  test('attach does not replay a location already taken', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();
    expect(service.takePendingLocation(), '/join?group=one');

    final navigated = <String>[];
    service.attach(navigated.add);
    expect(navigated, isEmpty);
  });

  test('attach flushes a link received after take', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();
    expect(service.takePendingLocation(), '/join?group=one');

    controller.add(Uri.parse('https://wishtogether.gift/group/two'));
    await pumpEventQueue();

    final navigated = <String>[];
    service.attach(navigated.add);
    expect(navigated, ['/group/two']);
  });

  test('forwards links received after attach', () async {
    final navigated = <String>[];
    service.attach(navigated.add);

    controller.add(Uri.parse('https://wishtogether.gift/wishlist/three'));
    await pumpEventQueue();

    expect(navigated, ['/wishlist/three']);
  });

  test('ignores foreign hosts and non-https links', () async {
    final navigated = <String>[];
    service.attach(navigated.add);

    controller
      ..add(Uri.parse('https://example.test/join?group=one'))
      ..add(Uri.parse('http://wishtogether.gift/join?group=two'));
    await pumpEventQueue();

    expect(navigated, isEmpty);
    expect(service.takePendingLocation(), isNull);
  });
  test('a rejected link does not replace a queued link', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();

    controller.add(Uri.parse('https://example.test/join?group=two'));
    await pumpEventQueue();

    expect(service.takePendingLocation(), '/join?group=one');
  });

  test('reports a link stream failure through the log', () async {
    final sink = RecordingSink();
    getIt.registerSingleton<AppLog>(
      AppLog(session: testSession, sinks: <LogSink>[sink]),
    );
    addTearDown(getIt.reset);

    controller.addError(StateError('link stream failed'));
    await pumpEventQueue();

    final event = sink.eventsOf<ErrorEvent>().single;
    expect(event.code, 'link-stream-failed');
  });
}
