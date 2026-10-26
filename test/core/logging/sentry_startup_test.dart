import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wishtogether/core/logging/sentry_startup.dart';
import 'package:wishtogether/core/logging/session_context.dart';

const String dsn = 'https://public@example.invalid/1';
const String webBuild = 'abc123';
const String iosBuild = '57';

PackageInfo packageInfoWith(String buildNumber) => PackageInfo(
  appName: 'WishTogether',
  packageName: 'gift.wishtogether',
  version: '1.0.0',
  buildNumber: buildNumber,
);

void main() {
  group('SentryStartup', () {
    test('names the production environment in a release build', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: iosBuild, platform: 'ios'),
        releaseMode: true,
        dsn: dsn,
      );

      expect(startup.environment, 'production');
    });

    test('names the debug environment outside a release build', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: iosBuild, platform: 'ios'),
        releaseMode: false,
        dsn: dsn,
      );

      expect(startup.environment, 'debug');
    });

    test('honours the staging override', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: iosBuild, platform: 'ios'),
        releaseMode: true,
        dsn: dsn,
        environment: 'staging',
      );

      expect(startup.environment, 'staging');
    });

    test('omits release and dist for a staging build', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: iosBuild, platform: 'ios'),
        releaseMode: true,
        dsn: dsn,
        environment: 'staging',
      );

      expect(startup.release, isNull);
      expect(startup.dist, isNull);
    });

    test('names release and dist from the build identity', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: webBuild, platform: 'web'),
        releaseMode: true,
        dsn: dsn,
      );

      expect(startup.release, 'wishtogether@$webBuild');
      expect(startup.dist, 'web-$webBuild');
    });

    test('writes the §4.5 option values verbatim', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: webBuild, platform: 'web'),
        releaseMode: true,
        dsn: dsn,
        environment: 'production',
      );
      final options = SentryFlutterOptions();

      startup.configure(options);

      expect(options.dsn, dsn);
      expect(options.environment, 'production');
      expect(options.release, 'wishtogether@$webBuild');
      expect(options.dist, 'web-$webBuild');
      expect(options.tracesSampleRate, 0);
      expect(options.enableAutoSessionTracking, isTrue);
      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.maxBreadcrumbs, 30);
      expect(options.replay.sessionSampleRate, 0);
      expect(options.replay.onErrorSampleRate, 0);
      expect(options.beforeSend, isNotNull);
      expect(options.beforeBreadcrumb, isNotNull);
    });
  });

  group('DSN gating', () {
    test('stays disabled without a DSN', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: webBuild, platform: 'web'),
        releaseMode: true,
        dsn: '',
      );

      expect(sentryDsnConfigured(startup.dsn), isFalse);
    });

    test('treats a whitespace-only DSN as absent', () {
      final startup = SentryStartup.fromEnvironment(
        identity: const BuildIdentity(build: webBuild, platform: 'web'),
        releaseMode: true,
        dsn: '   ',
      );

      expect(sentryDsnConfigured(startup.dsn), isFalse);
    });
  });

  group('platformTagFor', () {
    test('names web regardless of the host platform', () {
      expect(
        platformTagFor(isWeb: true, platform: TargetPlatform.android),
        'web',
      );
    });

    test('names the native platform in lowercase', () {
      expect(platformTagFor(isWeb: false, platform: TargetPlatform.iOS), 'ios');
    });
  });

  group('sentryDsnConfigured', () {
    test('treats empty and whitespace as absent', () {
      expect(sentryDsnConfigured(''), isFalse);
      expect(sentryDsnConfigured('   '), isFalse);
    });

    test('accepts a real DSN', () {
      expect(sentryDsnConfigured(dsn), isTrue);
    });
  });

  group('readBuildIdentity', () {
    test('uses the compile-time build on web', () async {
      final identity = await readBuildIdentity(
        isWeb: true,
        platform: TargetPlatform.android,
      );

      expect(identity.build, resolveBuildId(wtBuildId));
      expect(identity.platform, 'web');
    });

    test('reads CFBundleVersion on iOS', () async {
      final identity = await readBuildIdentity(
        isWeb: false,
        platform: TargetPlatform.iOS,
        loadPackageInfo: () async => packageInfoWith(iosBuild),
      );

      expect(identity.build, iosBuild);
      expect(identity.platform, 'ios');
    });

    test('falls back to the dev build when the platform read fails', () async {
      final identity = await readBuildIdentity(
        isWeb: false,
        platform: TargetPlatform.iOS,
        loadPackageInfo: () async => throw StateError('no bundle'),
      );

      expect(identity.build, devBuildId);
    });
  });
}
