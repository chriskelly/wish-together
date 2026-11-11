import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/main.dart';

void main() {
  testWidgets('the app root disables automatic retry', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(WishTogetherApp(router: router));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.retry, same(disableAutomaticRetry));
  });

  testWidgets('a failing provider under disableAutomaticRetry builds once', (
    tester,
  ) async {
    var builds = 0;
    final failing = FutureProvider<int>((ref) async {
      builds++;
      // An Exception, not an Error: Riverpod's default retry skips Error but
      // retries this 10 times, so the counter actually proves the policy.
      throw Exception('boom');
    });

    await tester.pumpWidget(
      ProviderScope(
        retry: disableAutomaticRetry,
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(failing);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(builds, 1);
  });
}
