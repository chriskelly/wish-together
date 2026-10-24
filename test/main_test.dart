import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/app_urls.dart';
import 'package:wishtogether/core/deep_links.dart';
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
}
