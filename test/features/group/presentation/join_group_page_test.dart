import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/group/application/join_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';
import 'package:wishtogether/features/group/presentation/join_group_page.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockGroupRepository extends Mock implements GroupRepository {}

class MockJoinGroupUseCase extends Mock implements JoinGroupUseCase {}

void main() {
  const groupId = 'group-1';
  const viewerId = 'viewer-uid';
  const ownerId = 'owner-uid';
  final group = Group(
    id: groupId,
    name: 'Family',
    ownerId: ownerId,
    members: [ownerId, viewerId],
  );
  final groupPath = GroupDetailsPage.route.replaceFirst(':id', groupId);

  late MockAuthSession session;
  late MockGroupRepository groupRepository;
  late MockJoinGroupUseCase joinGroupUseCase;
  late List<Uri> locationChanges;

  setUp(() {
    getIt.reset();
    session = MockAuthSession();
    when(() => session.currentUserId).thenReturn(viewerId);
    groupRepository = MockGroupRepository();
    joinGroupUseCase = MockJoinGroupUseCase();
    locationChanges = [];

    getIt.registerSingleton<AuthSession>(session);
    getIt.registerSingleton<GroupRepository>(groupRepository);
    getIt.registerSingleton<JoinGroupUseCase>(joinGroupUseCase);
  });

  tearDown(getIt.reset);

  /// Mounts the invite route and the group details route in the shape the app
  /// uses: group details nested under home, so the back stack after a redirect
  /// can be inspected as it would be in production.
  Future<GoRouter> pumpInvite(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/join?${JoinGroupPage.groupIdParam}=$groupId',
      routes: [
        GoRoute(
          path: JoinGroupPage.route,
          name: JoinGroupPage.routeName,
          builder: (context, state) => JoinGroupPage(
            groupId: state.uri.queryParameters[JoinGroupPage.groupIdParam]!,
          ),
        ),
        GoRoute(
          path: HomePage.route,
          builder: (context, state) => const Scaffold(body: Text('home')),
          routes: [
            GoRoute(
              path: GroupDetailsPage.route.substring(1),
              name: GroupDetailsPage.routeName,
              builder: (context, state) =>
                  Scaffold(body: Text('group ${state.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    router.routeInformationProvider.addListener(
      () => locationChanges.add(router.routeInformationProvider.value.uri),
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  Iterable<String> changedPaths() => locationChanges.map((uri) => uri.path);

  Iterable<String> matchedLocations(GoRouter router) => router
      .routerDelegate
      .currentConfiguration
      .matches
      .map((match) => match.matchedLocation);

  testWidgets('lands on the group without a tap when the user already '
      'belongs to it', (tester) async {
    when(() => groupRepository.get(groupId)).thenAnswer((_) async => group);

    final router = await pumpInvite(tester);
    await tester.pump();
    await tester.pump();
    // The location swap runs a page transition; let it finish so the invite
    // page is really gone rather than still fading out.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('group $groupId'), findsOneWidget);
    expect(find.text('Join Group'), findsNothing);
    expect(find.byType(JoinGroupPage), findsNothing);
    expect(changedPaths(), [groupPath]);
    expect(matchedLocations(router), isNot(contains(JoinGroupPage.route)));
  });

  testWidgets('replaces the browser history entry when redirecting an '
      'existing member', (tester) async {
    when(() => groupRepository.get(groupId)).thenAnswer((_) async => group);

    final messenger = tester.binding.defaultBinaryMessenger;
    final reports = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        reports.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.navigation, null),
    );

    await pumpInvite(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final groupReports = reports
        .where((report) => (report['uri']! as String).endsWith(groupPath))
        .toList();
    expect(groupReports, isNotEmpty);
    expect(
      groupReports.last['replace'],
      isTrue,
      reason:
          'the engine must replace the invite entry, or Back returns to '
          '/join and forwards again',
    );
  });

  testWidgets('reads the group once when the page rebuilds', (tester) async {
    final pending = Completer<Group>();
    when(() => groupRepository.get(groupId)).thenAnswer((_) => pending.future);

    await pumpInvite(tester);
    await tester.pump();

    tester.element(find.byType(JoinGroupPage)).markNeedsBuild();
    await tester.pump();

    pending.complete(group);
    await tester.pump();
    await tester.pump();

    verify(() => groupRepository.get(groupId)).called(1);
    expect(changedPaths(), [groupPath]);
  });

  testWidgets('follows a second invite link to a different group', (
    tester,
  ) async {
    const otherGroupId = 'group-2';
    when(() => groupRepository.get(groupId))
        .thenAnswer((_) async => group.copyWith(members: [ownerId]));
    when(() => groupRepository.get(otherGroupId)).thenAnswer(
      (_) async =>
          group.copyWith(id: otherGroupId, name: 'Work', members: [ownerId]),
    );

    final router = await pumpInvite(tester);
    await tester.pumpAndSettle();
    expect(find.text('Family'), findsOneWidget);

    router.go('/join?${JoinGroupPage.groupIdParam}=$otherGroupId');
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Family'), findsNothing);
    verify(() => groupRepository.get(otherGroupId)).called(1);
  });

  testWidgets('shows the invitation when the user is not a member', (
    tester,
  ) async {
    final notAMember = group.copyWith(members: [ownerId]);
    when(() => groupRepository.get(groupId))
        .thenAnswer((_) async => notAMember);

    final router = await pumpInvite(tester);
    await tester.pumpAndSettle();

    expect(find.text("You've been invited to join"), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Join Group'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, JoinGroupPage.route);
  });

  testWidgets('shows the invitation when nobody is signed in', (tester) async {
    when(() => session.currentUserId).thenReturn(null);
    when(() => groupRepository.get(groupId)).thenAnswer((_) async => group);

    final router = await pumpInvite(tester);
    await tester.pumpAndSettle();

    expect(find.text("You've been invited to join"), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, JoinGroupPage.route);
  });

  testWidgets('shows the invalid-invitation message when the group cannot be '
      'loaded', (tester) async {
    when(() => groupRepository.get(groupId))
        .thenAnswer((_) async => throw StateError('group is gone'));

    final router = await pumpInvite(tester);
    await tester.pumpAndSettle();

    expect(find.text('This invitation is no longer valid.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, JoinGroupPage.route);
  });

  testWidgets('keeps the loading state while the group is being fetched', (
    tester,
  ) async {
    final pending = Completer<Group>();
    when(() => groupRepository.get(groupId)).thenAnswer((_) => pending.future);

    await pumpInvite(tester);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("You've been invited to join"), findsNothing);

    pending.complete(group.copyWith(members: [ownerId]));
    await tester.pumpAndSettle();

    expect(find.text("You've been invited to join"), findsOneWidget);
  });

  testWidgets('still joins and lands on the group when Join Group is tapped', (
    tester,
  ) async {
    final notAMember = group.copyWith(members: [ownerId]);
    when(() => groupRepository.get(groupId))
        .thenAnswer((_) async => notAMember);
    when(() => joinGroupUseCase.execute(groupId)).thenAnswer((_) async {});

    final router = await pumpInvite(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join Group'));
    // The joining spinner never stops if the redirect breaks, so settle with a
    // bounded timeout instead of the ten-minute default: a regression should
    // report itself in seconds.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    verify(() => joinGroupUseCase.execute(groupId)).called(1);
    expect(find.text('group $groupId'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, groupPath);
  });
}
