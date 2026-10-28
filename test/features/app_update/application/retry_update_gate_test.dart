import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/app_update/application/retry_update_gate.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

import '../../../core/logging/recording_sink.dart';

void main() {
  group('retryUpdateGate', () {
    test('does not start the app when the retry is blocked', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.blocked(
          message: 'Update',
          updateUrl: 'https://apps.apple.com/app/id1234567890',
        ),
        start: () => started = true,
      );

      // Assert
      expect(result, isFalse);
      expect(started, isFalse);
    });

    test('does not start the app when the retry fails open', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.allowed(),
        start: () => started = true,
      );

      // Assert
      expect(result, isFalse);
      expect(started, isFalse);
    });

    test('starts the app when the retry is conclusive', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.allowed(isConclusive: true),
        start: () => started = true,
      );

      // Assert
      expect(result, isTrue);
      expect(started, isTrue);
    });

    test('stays blocked when the check throws', () async {
      // Arrange
      var started = false;

      // Act
      final result = await retryUpdateGate(
        check: () async => throw Exception('unavailable'),
        start: () => started = true,
      );

      // Assert
      expect(result, isFalse);
      expect(started, isFalse);
    });

    test('reports failure when starting the app throws', () async {
      // Act
      final result = await retryUpdateGate(
        check: () async => const UpdateDecision.allowed(isConclusive: true),
        start: () => throw Exception('cannot start'),
      );

      // Assert
      expect(result, isFalse);
    });
  });

  group('retryUpdateGate diagnostics', () {
    late RecordingSink sink;

    setUp(() async {
      await getIt.reset();
      sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
    });

    tearDown(getIt.reset);

    test(
      'reports the throwing retry as an error, not a gate decision',
      () async {
        await retryUpdateGate(
          check: () async => throw Exception('unavailable'),
          start: () {},
        );

        final events = sink.eventsOf<ErrorEvent>().toList();
        expect(events, hasLength(1));
        expect(events.single.code, 'retry-failed');
        expect(sink.eventsOf<UpdateGateEvent>(), isEmpty);
      },
    );
  });
}
