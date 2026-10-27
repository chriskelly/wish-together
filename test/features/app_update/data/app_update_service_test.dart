import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/platform_info.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/app_update/data/app_update_service.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

import '../../../core/logging/recording_sink.dart';
import '../../../core/logging/wire_absence.dart';

class MockRemoteConfig extends Mock implements FirebaseRemoteConfig {}

/// [RemoteConfigValue]'s constructor is protected; a subclass may use it.
class _FakeRemoteConfigValue extends RemoteConfigValue {
  _FakeRemoteConfigValue(super.value, super.source);
}

PackageInfo packageInfoWith({String buildNumber = '1'}) => PackageInfo(
  appName: 'WishTogether',
  packageName: 'gift.wishtogether',
  version: '1.0.0',
  buildNumber: buildNumber,
);

/// Captures the gate's own events, which replace its direct debug output.
RecordingSink captureGateEvents() {
  final sink = RecordingSink();
  getIt.registerSingleton<AppLog>(
    AppLog(session: testSession, sinks: <LogSink>[sink]),
  );
  addTearDown(getIt.reset);
  return sink;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      RemoteConfigSettings(
        fetchTimeout: Duration.zero,
        minimumFetchInterval: Duration.zero,
      ),
    );
    registerFallbackValue(<String, dynamic>{});
  });

  group('AppUpdateService', () {
    late MockRemoteConfig remoteConfig;

    setUp(() {
      remoteConfig = MockRemoteConfig();
      when(() => remoteConfig.setDefaults(any())).thenAnswer((_) async {});
      when(() => remoteConfig.setConfigSettings(any()))
          .thenAnswer((_) async {});
      when(() => remoteConfig.fetchAndActivate()).thenAnswer((_) async => true);
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(0);
      when(() => remoteConfig.getString(AppUpdateService.updateMessageKey))
          .thenReturn('');
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn('');
      when(() => remoteConfig.getValue(any()))
          .thenReturn(_FakeRemoteConfigValue(null, ValueSource.valueStatic));
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    AppUpdateService serviceWith({
      String buildNumber = '1',
      bool bypassGate = false,
      bool? gateApplies = true,
      Duration fetchTimeout = AppUpdateService.defaultFetchTimeout,
      Duration totalTimeout = AppUpdateService.defaultTotalTimeout,
      PackageInfoLoader? packageInfoLoader,
    }) {
      return AppUpdateService(
        remoteConfig: remoteConfig,
        packageInfoLoader:
            packageInfoLoader ??
            () async => packageInfoWith(buildNumber: buildNumber),
        bypassGate: bypassGate,
        gateApplies: gateApplies,
        fetchTimeout: fetchTimeout,
        totalTimeout: totalTimeout,
      );
    }

    test('fails open when Remote Config throws', () async {
      // Arrange
      when(() => remoteConfig.fetchAndActivate())
          .thenThrow(Exception('offline'));
      final events = captureGateEvents();
      final service = serviceWith();

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'remote-config-unavailable');
    });

    test('fails open when Remote Config does not answer in time', () async {
      // Arrange
      when(() => remoteConfig.fetchAndActivate())
          .thenAnswer((_) => Completer<bool>().future);
      final events = captureGateEvents();
      final service = serviceWith(
        fetchTimeout: const Duration(milliseconds: 10),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'remote-config-unavailable');
    });

    test('fails open when the whole check hangs', () async {
      // Arrange
      final events = captureGateEvents();
      final service = serviceWith(
        packageInfoLoader: () => Completer<PackageInfo>().future,
        totalTimeout: const Duration(milliseconds: 10),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'check-failed');
    });

    test(
      'starts the Remote Config fetch without waiting for the build',
      () async {
        // Arrange
        final packageInfoCompleter = Completer<PackageInfo>();
        final service = serviceWith(
          packageInfoLoader: () => packageInfoCompleter.future,
        );

        // Act
        final decisionFuture = service.check();
        await Future<void>.delayed(Duration.zero);

        // Assert
        verify(() => remoteConfig.fetchAndActivate()).called(1);

        packageInfoCompleter.complete(packageInfoWith());
        final decision = await decisionFuture;
        expect(decision.isBlocked, isFalse);
      },
    );

    test('reuses a successful build read across checks', () async {
      // Arrange
      var loads = 0;
      final service = serviceWith(
        packageInfoLoader: () async {
          loads++;
          return packageInfoWith();
        },
      );

      // Act
      await service.check();
      await service.check();

      // Assert
      expect(loads, 1);
    });

    test('caches a zero build number', () async {
      // Arrange
      var loads = 0;
      final service = serviceWith(
        packageInfoLoader: () async {
          loads++;
          return packageInfoWith(buildNumber: '0');
        },
      );

      // Act
      await service.check();
      await service.check();

      // Assert
      expect(loads, 1);
    });

    test('retries the build read after a failure', () async {
      // Arrange
      var loads = 0;
      final service = serviceWith(
        packageInfoLoader: () async {
          loads++;
          if (loads == 1) {
            throw Exception('unavailable');
          }
          return packageInfoWith();
        },
      );

      // Act
      final first = await service.check();
      final second = await service.check();

      // Assert
      expect(first.isConclusive, isFalse);
      expect(second.isConclusive, isTrue);
      expect(loads, 2);
    });

    test('blocks when the running build is below the minimum', () async {
      // Arrange
      const minSupportedBuild = 20;
      const runningBuild = minSupportedBuild - 1;
      const message = 'Please update WishTogether.';
      const updateUrl = 'https://apps.apple.com/app/id1234567890';
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(minSupportedBuild);
      when(() => remoteConfig.getString(AppUpdateService.updateMessageKey))
          .thenReturn(message);
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn(updateUrl);
      final events = captureGateEvents();
      final service = serviceWith(buildNumber: '$runningBuild');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isTrue);
      expect(decision.isConclusive, isTrue);
      expect(decision.message, message);
      expect(decision.updateUrl, updateUrl);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.blocked);
      expect(event.min, minSupportedBuild);
      expect(event.running, runningBuild);
    });

    test('stays inert when the minimum is zero', () async {
      // Arrange
      final service = serviceWith();

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isTrue);
    });

    test('fails open when the build number is not an integer', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final events = captureGateEvents();
      final service = serviceWith(buildNumber: 'not-a-number');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'build-unreadable');
    });

    test('fails open when the build number is missing', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final events = captureGateEvents();
      final service = serviceWith(buildNumber: '');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'build-unreadable');
    });

    test('fails open when the build loader throws', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final events = captureGateEvents();
      final service = serviceWith(
        packageInfoLoader: () async => throw Exception('unavailable'),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'build-unreadable');
    });

    test('honours the maintainer bypass', () async {
      // Arrange
      var loads = 0;
      final events = captureGateEvents();
      final service = serviceWith(
        bypassGate: true,
        packageInfoLoader: () async {
          loads++;
          return packageInfoWith();
        },
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isTrue);
      expect(loads, 0);
      verifyNever(() => remoteConfig.fetchAndActivate());
      expect(events.eventsOf<UpdateGateEvent>().single.reason, 'debug-bypass');
    });

    test('uses the default message when Remote Config provides none', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn('https://apps.apple.com/app/id1234567890');
      final service = serviceWith(buildNumber: '19');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.message, defaultUpdateMessage);
    });

    test('fails open and logs when a block has no usable update URL', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final events = captureGateEvents();
      final service = serviceWith(buildNumber: '19');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'missing-update-url');
    });

    test('fails open when the update URL is not a store URL', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn('javascript:alert(1)');
      final service = serviceWith(buildNumber: '19');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('reads values even when fetchAndActivate reports no change', () async {
      // Arrange
      const minSupportedBuild = 20;
      when(() => remoteConfig.fetchAndActivate())
          .thenAnswer((_) async => false);
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(minSupportedBuild);
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn('https://apps.apple.com/app/id1234567890');
      final service = serviceWith(buildNumber: '19');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isTrue);
      expect(decision.isConclusive, isTrue);
    });

    test('registers inert defaults and per-launch settings', () async {
      // Arrange
      final service = serviceWith();

      // Act
      await service.check();

      // Assert
      final defaults =
          verify(() => remoteConfig.setDefaults(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(defaults[AppUpdateService.minSupportedBuildKey], 0);
      expect(defaults[AppUpdateService.updateMessageKey], '');
      expect(defaults[AppUpdateService.updateUrlKey], '');

      final settings =
          verify(() => remoteConfig.setConfigSettings(captureAny()))
                  .captured
                  .single
              as RemoteConfigSettings;
      expect(settings.fetchTimeout, AppUpdateService.defaultFetchTimeout);
      expect(settings.minimumFetchInterval, Duration.zero);
    });

    test('warns on the decision record when min is not an integer', () async {
      // Arrange
      const minSupportedBuild = 20;
      const runningBuild = 1;
      final events = captureGateEvents();
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(minSupportedBuild);
      when(() => remoteConfig.getValue(AppUpdateService.minSupportedBuildKey))
          .thenReturn(
            _FakeRemoteConfigValue(utf8.encode('v20'), ValueSource.valueRemote),
          );
      final service = serviceWith(buildNumber: '$runningBuild');

      // Act
      await service.check();

      // Assert: one record, and it is the decision — not an early warning that
      // replaces it. Both bounds must survive.
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.reason, 'min-not-integer');
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.min, minSupportedBuild);
      expect(event.running, runningBuild);
    });

    test('stays quiet when min_supported_build is an integer', () async {
      // Arrange
      final events = captureGateEvents();
      when(() => remoteConfig.getValue(AppUpdateService.minSupportedBuildKey))
          .thenReturn(
            _FakeRemoteConfigValue(utf8.encode('20'), ValueSource.valueRemote),
          );
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn('https://apps.apple.com/app/id1234567890');
      final service = serviceWith();

      // Act
      await service.check();

      // Assert: an ordinary blocked decision, with no configuration warning.
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.blocked);
      expect(event.reason, isNull);
    });

    test('the decision record carries no update message text', () async {
      // Arrange: the message is real and reaches the screen, so its absence
      // from the wire is a property of the event, not of an empty message.
      const phoneNumber = '+15555550123';
      const itemId = 'item-7f3a9c1d2e';
      const updateMessageToken = 'MAINTENANCE-WINDOW-42';
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      when(() => remoteConfig.getString(AppUpdateService.updateMessageKey))
          .thenReturn('Maintenance $updateMessageToken for $phoneNumber');
      when(() => remoteConfig.getString(AppUpdateService.updateUrlKey))
          .thenReturn('https://apps.apple.com/app/id1234567890');
      final events = captureGateEvents();
      final service = serviceWith(buildNumber: '19');

      // Act
      final decision = await service.check();

      // Assert: the message reaches the screen but not the record — checked at
      // the emitter as well as on the wire, because the wire redactor would
      // hide a leak that reached the event.
      expect(decision.message, contains(updateMessageToken));
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.reason, isNull, reason: 'the message must not ride reason');
      expect(event.result, UpdateGateResult.blocked);
      expectNoSensitiveValues(events.records, <String>[
        phoneNumber,
        itemId,
        updateMessageToken,
      ]);
    });

    test('reports one decision when the timeout beats a late _check', () async {
      // Arrange: the build resolves only after the whole-check bound fired.
      final events = captureGateEvents();
      final packageInfo = Completer<PackageInfo>();
      final service = serviceWith(
        packageInfoLoader: () => packageInfo.future,
        totalTimeout: const Duration(milliseconds: 10),
      );

      // Act: the check fails open on the timeout ...
      final decision = await service.check();
      // ... and then the slow plugin call completes, letting the abandoned
      // _check reach its own decision.
      packageInfo.complete(packageInfoWith());
      await pumpEventQueue();

      // Assert: one decision for the launch, and it is the timeout's.
      expect(decision.isBlocked, isFalse);
      final event = events.eventsOf<UpdateGateEvent>().single;
      expect(event.result, UpdateGateResult.failedOpen);
      expect(event.reason, 'check-failed');
    });

    group('platform policy', () {
      test('applies on iOS', () async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final service = serviceWith(gateApplies: null);

        // Act
        await service.check();

        // Assert
        verify(() => remoteConfig.fetchAndActivate()).called(1);
      });

      test('does not apply on Android', () async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final events = captureGateEvents();
        final service = serviceWith(gateApplies: null);

        // Act
        final decision = await service.check();

        // Assert
        expect(decision.isBlocked, isFalse);
        verifyNever(() => remoteConfig.fetchAndActivate());
        expect(
          events.eventsOf<UpdateGateEvent>().single.reason,
          'gate-not-applicable',
        );
      });

      test('does not apply on macOS', () async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final service = serviceWith(gateApplies: null);

        // Act
        final decision = await service.check();

        // Assert
        expect(decision.isBlocked, isFalse);
        verifyNever(() => remoteConfig.fetchAndActivate());
      });
    });
  });

  group('gateAppliesOn', () {
    test('gates iOS', () {
      expect(gateAppliesOn(isWeb: false, platform: TargetPlatform.iOS), isTrue);
    });

    test('does not gate web, where the build number is not comparable', () {
      // kIsWeb is a compile-time constant, so the browser is simulated here.
      // Dropping the web exclusion from the predicate must fail this test.
      expect(gateAppliesOn(isWeb: true, platform: TargetPlatform.iOS), isFalse);
    });

    test('does not gate other platforms', () {
      expect(
        gateAppliesOn(isWeb: false, platform: TargetPlatform.android),
        isFalse,
      );
    });
  });
}
