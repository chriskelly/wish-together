import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/app_urls.dart';
import 'package:wishtogether/core/deep_links.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';

import 'core/logging/recording_sink.dart';

import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/main.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applies a queued link and forwards warm links', () async {
    final auth = MockAuthService();
    final repository = MockUserRepository();
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
    getIt.registerSingleton<UserRepository>(repository);
    addTearDown(getIt.reset);

    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final links = DeepLinkService(
      links: controller.stream,
      allowedHosts: releaseUniversalLinkHosts,
    );

    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();

    WishTogetherApp? mounted;
    startApp(links: links, auth: auth, mount: (app) => mounted = app);

    expect(
      mounted!.router.routeInformationProvider.value.uri.toString(),
      '/join?group=one',
    );

    controller.add(Uri.parse('https://wishtogether.gift/group/two'));
    await pumpEventQueue();

    expect(
      mounted!.router.routeInformationProvider.value.uri.toString(),
      '/group/two',
    );
  });

  test('reports one session start carrying the real identifiers', () async {
    final auth = MockAuthService();
    final repository = MockUserRepository();
    final sink = RecordingSink();
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
    getIt.registerSingleton<UserRepository>(repository);
    getIt.registerSingleton<AppLog>(
      AppLog(session: testSession, sinks: <LogSink>[sink]),
    );
    addTearDown(getIt.reset);

    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final links = DeepLinkService(
      links: controller.stream,
      allowedHosts: releaseUniversalLinkHosts,
    );
    controller.add(Uri.parse('https://wishtogether.gift/join?group=one'));
    await pumpEventQueue();

    startApp(links: links, auth: auth, mount: (_) {});

    final starts = sink.eventsOf<SessionStartEvent>().toList();
    expect(starts, hasLength(1));
    expect(starts.single.build, testSession.build);
    expect(starts.single.platform, testSession.platform);
    expect(starts.single.route, '/join');
    expect(
      sink.records.last.session.route,
      '/join',
      reason: 'the session must carry the route it opened on',
    );
  });
}
