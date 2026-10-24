import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/app_urls.dart';
import 'package:wishtogether/core/deep_links.dart';

Future<void> settle() => pumpEventQueue();

void main() {
  late StreamController<Uri> controller;
  late DeepLinkService service;

  setUp(() {
    controller = StreamController<Uri>.broadcast();
    service = DeepLinkService(
      links: controller.stream,
      allowedHosts: releaseUniversalLinkHosts,
    );
  });

  tearDown(() => controller.close());

  test('queues a link received before startup', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await settle();

    expect(service.takePendingLocation(), '/join?group=one');
  });

  test('the latest link wins before startup', () async {
    controller
      ..add(Uri.parse('https://wishtogether.gift/join?group=one'))
      ..add(Uri.parse('https://wishtogether.gift/group/two'));
    await settle();

    expect(service.takePendingLocation(), '/group/two');
  });

  test('takePendingLocation consumes the queue', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await settle();

    expect(service.takePendingLocation(), '/join?group=one');
    expect(service.takePendingLocation(), isNull);
  });

  test('attach does not replay a location already taken', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await settle();
    expect(service.takePendingLocation(), '/join?group=one');

    final navigated = <String>[];
    service.attach(navigated.add);
    expect(navigated, isEmpty);
  });

  test('attach flushes a link received after take', () async {
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await settle();
    expect(service.takePendingLocation(), '/join?group=one');

    controller.add(Uri.parse('https://wishtogether.gift/group/two'));
    await settle();

    final navigated = <String>[];
    service.attach(navigated.add);
    expect(navigated, ['/group/two']);
  });

  test('forwards links received after attach', () async {
    final navigated = <String>[];
    service.attach(navigated.add);

    controller.add(Uri.parse('https://wishtogether.gift/wishlist/three'));
    await settle();

    expect(navigated, ['/wishlist/three']);
  });

  test('ignores foreign hosts and non-https links', () async {
    final navigated = <String>[];
    service.attach(navigated.add);

    controller
      ..add(Uri.parse('https://example.test/join?group=one'))
      ..add(Uri.parse('http://wishtogether.gift/join?group=two'));
    await settle();

    expect(navigated, isEmpty);
    expect(service.takePendingLocation(), isNull);
  });
}
