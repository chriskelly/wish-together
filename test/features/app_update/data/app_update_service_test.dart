import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wishtogether/features/app_update/data/app_update_service.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

class MockRemoteConfig extends Mock implements FirebaseRemoteConfig {}

/// [RemoteConfigValue]'s constructor is protected; a subclass may use it.
class _FakeRemoteConfigValue extends RemoteConfigValue {
  _FakeRemoteConfigValue(super.value, super.source);
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
            () async => PackageInfo(
              appName: 'WishTogether',
              packageName: 'gift.wishtogether',
              version: '1.0.0',
              buildNumber: buildNumber,
            ),
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
      final service = serviceWith();

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('fails open when Remote Config does not answer in time', () async {
      // Arrange
      when(() => remoteConfig.fetchAndActivate())
          .thenAnswer((_) => Completer<bool>().future);
      final service = serviceWith(
        fetchTimeout: const Duration(milliseconds: 10),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('fails open when the whole check hangs', () async {
      // Arrange
      final service = serviceWith(
        packageInfoLoader: () => Completer<PackageInfo>().future,
        totalTimeout: const Duration(milliseconds: 10),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
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
      final service = serviceWith(buildNumber: '$runningBuild');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isTrue);
      expect(decision.isConclusive, isTrue);
      expect(decision.message, message);
      expect(decision.updateUrl, updateUrl);
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
      final service = serviceWith(buildNumber: 'not-a-number');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('fails open when the build number is missing', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final service = serviceWith(buildNumber: '');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('fails open when the build loader throws', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final service = serviceWith(
        packageInfoLoader: () async => throw Exception('unavailable'),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
    });

    test('honours the maintainer bypass', () async {
      // Arrange
      final service = serviceWith(bypassGate: true);

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      verifyNever(() => remoteConfig.fetchAndActivate());
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

    test('fails open when a block has no usable update URL', () async {
      // Arrange
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final service = serviceWith(buildNumber: '19');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      expect(decision.isConclusive, isFalse);
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

    test('warns when min_supported_build is not an integer', () async {
      // Arrange
      final messages = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        messages.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);
      when(() => remoteConfig.getValue(AppUpdateService.minSupportedBuildKey))
          .thenReturn(
            _FakeRemoteConfigValue(utf8.encode('v20'), ValueSource.valueRemote),
          );
      final service = serviceWith();

      // Act
      await service.check();

      // Assert
      expect(
        messages.any((message) => message?.contains('not an integer') ?? false),
        isTrue,
      );
    });

    test('stays quiet when min_supported_build is an integer', () async {
      // Arrange
      final messages = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        messages.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);
      when(() => remoteConfig.getValue(AppUpdateService.minSupportedBuildKey))
          .thenReturn(
            _FakeRemoteConfigValue(utf8.encode('20'), ValueSource.valueRemote),
          );
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(20);
      final service = serviceWith();

      // Act
      await service.check();

      // Assert
      expect(
        messages.any((message) => message?.contains('not an integer') ?? false),
        isFalse,
      );
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
        final service = serviceWith(gateApplies: null);

        // Act
        final decision = await service.check();

        // Assert
        expect(decision.isBlocked, isFalse);
        verifyNever(() => remoteConfig.fetchAndActivate());
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
}
