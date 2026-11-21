import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/route_state.dart';

import '../support/router_state.dart';

class _ExpectedArgs {
  const _ExpectedArgs();
}

class _OtherArgs {
  const _OtherArgs();
}

void main() {
  group('routeExtra', () {
    test('returns the extra when it has the requested type', () {
      final router = stateFixtureRouter();
      addTearDown(router.dispose);
      const args = _ExpectedArgs();

      final result = routeExtra<_ExpectedArgs>(
        stateFixture(router, extra: args),
      );

      expect(result, same(args));
    });

    test('returns null when the navigation carried no extra', () {
      final router = stateFixtureRouter();
      addTearDown(router.dispose);

      final result = routeExtra<_ExpectedArgs>(stateFixture(router));

      expect(result, isNull);
    });

    test('returns null when the extra has another type', () {
      final router = stateFixtureRouter();
      addTearDown(router.dispose);

      final result = routeExtra<_ExpectedArgs>(
        stateFixture(router, extra: const _OtherArgs()),
      );

      expect(result, isNull);
    });
  });

  testWidgets('the unavailable page explains the dead end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RouteUnavailablePage()));

    expect(find.text(routeUnavailableMessage), findsOneWidget);
  });
}
