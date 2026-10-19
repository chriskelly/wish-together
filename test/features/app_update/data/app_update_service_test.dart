import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wishtogether/features/app_update/data/app_update_service.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

class MockRemoteConfig extends Mock implements FirebaseRemoteConfig {}

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
    });

    AppUpdateService serviceWith({
      required String buildNumber,
      bool bypassGate = false,
      bool gateApplies = true,
      Duration fetchTimeout = AppUpdateService.defaultFetchTimeout,
    }) {
      return AppUpdateService(
        remoteConfig: remoteConfig,
        packageInfoLoader: () async => PackageInfo(
          appName: 'WishTogether',
          packageName: 'gift.wishtogether',
          version: '1.0.0',
          buildNumber: buildNumber,
        ),
        bypassGate: bypassGate,
        gateApplies: gateApplies,
        fetchTimeout: fetchTimeout,
      );
    }

    test('fails open when Remote Config throws', () async {
      // Arrange
      const runningBuild = 10;
      when(() => remoteConfig.fetchAndActivate())
          .thenThrow(Exception('offline'));
      final service = serviceWith(buildNumber: '$runningBuild');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('fails open when Remote Config does not answer in time', () async {
      // Arrange
      when(() => remoteConfig.fetchAndActivate())
          .thenAnswer((_) => Completer<bool>().future);
      final service = serviceWith(
        buildNumber: '10',
        fetchTimeout: const Duration(milliseconds: 10),
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('blocks when the running build is below the minimum', () async {
      // Arrange
      const minSupportedBuild = 20;
      const runningBuild = minSupportedBuild - 1;
      const message = 'Please update WishTogether.';
      const updateUrl = 'https://example.com/update';
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
      expect(decision.message, message);
      expect(decision.updateUrl, updateUrl);
    });

    test('stays inert when the minimum is zero', () async {
      // Arrange
      const runningBuild = 1;
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(0);
      final service = serviceWith(buildNumber: '$runningBuild');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
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
    });

    test('honours the maintainer bypass', () async {
      // Arrange
      const minSupportedBuild = 20;
      const runningBuild = minSupportedBuild - 1;
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(minSupportedBuild);
      final service = serviceWith(
        buildNumber: '$runningBuild',
        bypassGate: true,
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
    });

    test('uses the default message when Remote Config provides none', () async {
      // Arrange
      const minSupportedBuild = 20;
      const runningBuild = minSupportedBuild - 1;
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(minSupportedBuild);
      final service = serviceWith(buildNumber: '$runningBuild');

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.message, defaultUpdateMessage);
    });

    test('never blocks on a platform where the gate does not apply', () async {
      // Arrange
      const minSupportedBuild = 20;
      const runningBuild = 1;
      when(() => remoteConfig.getInt(AppUpdateService.minSupportedBuildKey))
          .thenReturn(minSupportedBuild);
      final service = serviceWith(
        buildNumber: '$runningBuild',
        gateApplies: false,
      );

      // Act
      final decision = await service.check();

      // Assert
      expect(decision.isBlocked, isFalse);
      verifyNever(() => remoteConfig.fetchAndActivate());
    });

    test('registers a zero default before reading values', () async {
      // Arrange
      final service = serviceWith(buildNumber: '1');

      // Act
      await service.check();

      // Assert
      final defaults =
          verify(() => remoteConfig.setDefaults(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(defaults[AppUpdateService.minSupportedBuildKey], 0);
    });
  });
}
