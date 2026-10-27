import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/app_update/application/check_for_update.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

import '../../../core/logging/recording_sink.dart';

void main() {
  group('checkForUpdate', () {
    test('returns the check result unchanged', () async {
      // Arrange
      const decision = UpdateDecision.allowed(isConclusive: true);

      // Act
      final result = await checkForUpdate(() async => decision);

      // Assert
      expect(identical(result, decision), isTrue);
    });

    test('turns a throw into an inconclusive allowance', () async {
      // Act
      final result = await checkForUpdate(
        () async => throw Exception('unavailable'),
      );

      // Assert
      expect(result.isBlocked, isFalse);
      expect(result.isConclusive, isFalse);
    });

    test('reports the failed-open allowance as a warning event', () async {
      // Arrange
      final sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      addTearDown(getIt.reset);

      // Act
      await checkForUpdate(() async => throw Exception('unavailable'));

      // Assert
      final event = sink.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'unexpected-failure');
      expect(sink.eventsOf<ErrorEvent>(), isEmpty);
    });
  });
}
