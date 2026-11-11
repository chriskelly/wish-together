import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/providers.dart';

void main() {
  test('the root retry policy never retries', () {
    expect(disableAutomaticRetry(0, StateError('boom')), isNull);
    expect(disableAutomaticRetry(10, Exception('boom')), isNull);
  });

  testWidgets('a failing provider builds once under the root retry policy', (
    tester,
  ) async {
    var builds = 0;
    final failing = FutureProvider<int>((ref) async {
      builds++;
      throw StateError('boom');
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
