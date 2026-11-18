import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../platform_info.dart';
import 'session_context.dart';
import 'sentry_policy.dart';

/// DSN supplied at compile time.
///
/// Empty means Sentry is not initialised at all; the release workflows pass the
/// real value through `--dart-define`.
const String wtSentryDsn = String.fromEnvironment('WT_SENTRY_DSN');

/// Environment override supplied at compile time.
///
/// Empty means derive it: `production` in release builds, `debug` otherwise.
/// `staging` is the pre-merge host, which carries no release; `testflight` is
/// passed by the TestFlight lane.
const String wtSentryEnvironment = String.fromEnvironment(
  'WT_SENTRY_ENVIRONMENT',
);

/// A distinctive marker emitted into the compiled program so a lane can prove
/// the environment define reached the artifact, as `firestoreTargetStamp`
/// does for the Firestore database. The bare value is not a marker: Flutter
/// and its plugins contain words such as `testflight`.
const String sentryEnvironmentStampPrefix = 'wishtogether-sentry-environment=';
const String sentryEnvironmentStamp =
    '$sentryEnvironmentStampPrefix$wtSentryEnvironment';

/// Recovers the `WT_SENTRY_ENVIRONMENT` value from a compiled [stamp].
///
/// Startup resolves the override this way instead of reading
/// [wtSentryEnvironment] directly: a constant that nothing reads is removed by
/// the compiler, and the lane greps the shipped binary for
/// [sentryEnvironmentStamp]. A stamp without the prefix means no override.
String sentryEnvironmentOverrideFrom(String stamp) =>
    stamp.startsWith(sentryEnvironmentStampPrefix)
    ? stamp.substring(sentryEnvironmentStampPrefix.length)
    : '';

const String _productionEnvironment = 'production';
const String _stagingEnvironment = 'staging';
const String _debugEnvironment = 'debug';

/// Whether a configured DSN should start Sentry.
///
/// Whitespace is absent, not a DSN; the composition root gates on this
/// predicate.
bool sentryDsnConfigured(String dsn) => dsn.trim().isNotEmpty;

/// The `platform` tag value: `web`, `ios`, `android`, …
String platformTagFor({
  required bool isWeb,
  required TargetPlatform platform,
}) => isWeb ? 'web' : platform.name.toLowerCase();

/// The Sentry environment of this build.
String environmentFor({required bool releaseMode, required String override}) {
  final value = override.trim();
  if (value.isNotEmpty) {
    return value;
  }
  return releaseMode ? _productionEnvironment : _debugEnvironment;
}

/// `wishtogether@<build>`, the release name.
String releaseNameFor(String build) => 'wishtogether@$build';

/// `<platform>-<build>`, the dist name.
String distNameFor(String platform, String build) => '$platform-$build';

/// Build identity of this launch: the web commit SHA, or iOS's
/// `CFBundleVersion`.
class BuildIdentity {
  const BuildIdentity({required this.build, required this.platform});

  final String build;
  final String platform;
}

/// Reads the launch identity, falling back to [devBuildId].
///
/// Web uses the compile-time `WT_BUILD_ID` (the commit SHA) and never touches a
/// plugin. iOS reads `CFBundleVersion` through `package_info_plus`, the same
/// source `AppUpdateService` already uses; a failed or malformed read degrades
/// to [devBuildId] rather than blocking startup.
Future<BuildIdentity> readBuildIdentity({
  required bool isWeb,
  required TargetPlatform platform,
  PackageInfoLoader? loadPackageInfo,
}) async {
  final tag = platformTagFor(isWeb: isWeb, platform: platform);
  if (isWeb) {
    return BuildIdentity(build: resolveBuildId(wtBuildId), platform: tag);
  }
  var raw = '';
  try {
    raw = (await (loadPackageInfo ?? PackageInfo.fromPlatform)()).buildNumber;
  } catch (_) {
    // Diagnostics must never delay or break startup.
  }
  return BuildIdentity(build: resolveBuildId(raw), platform: tag);
}

/// The Sentry configuration, as data.
///
/// The option values are pure: constructing one reads no globals, so they can
/// be asserted in a VM test. [readIdentity] is the composition-root helper that
/// does read the platform. `main.dart` only decides whether to hand this to
/// `SentryFlutter.init`.
class SentryStartup {
  const SentryStartup({
    required this.dsn,
    required this.environment,
    required this.identity,
  });

  /// Builds the configuration from the compile-time defines.
  ///
  /// [environment] overrides the compiled value; null reads the override from
  /// the marker compiled into this binary. [stamp] names that marker and lets a
  /// test drive the compiled path without a `--dart-define`.
  factory SentryStartup.fromEnvironment({
    required BuildIdentity identity,
    required bool releaseMode,
    String dsn = wtSentryDsn,
    String? environment,
    String? stamp,
  }) => SentryStartup(
    dsn: dsn.trim(),
    environment: environmentFor(
      releaseMode: releaseMode,
      override:
          environment ??
          sentryEnvironmentOverrideFrom(stamp ?? sentryEnvironmentStamp),
    ),
    identity: identity,
  );

  final String dsn;
  final String environment;
  final BuildIdentity identity;

  /// True for the pre-merge host, which deploys without a release.
  bool get isStaging => environment == _stagingEnvironment;

  String? get release => isStaging ? null : releaseNameFor(identity.build);

  String? get dist =>
      isStaging ? null : distNameFor(identity.platform, identity.build);

  /// Applies the Sentry values. Kept in one place so the policy is testable.
  void configure(SentryFlutterOptions options) {
    options
      ..dsn = dsn
      ..environment = environment
      ..release = release
      ..dist = dist
      ..tracesSampleRate = 0
      ..enableAutoSessionTracking = true
      ..sendDefaultPii = false
      ..attachScreenshot = false
      ..maxBreadcrumbs = 30
      // ConsoleSink already prints in debug; the SDK's own print breadcrumbs
      // would duplicate every record.
      ..enablePrintBreadcrumbs = false
      ..beforeSend = scrubEvent
      ..beforeBreadcrumb = scrubBreadcrumb;
    options.replay
      ..sessionSampleRate = 0
      ..onErrorSampleRate = 0;
    if (isStaging) {
      // The SDK's release integration fills release/dist from PackageInfo when
      // they are null, which would give staging a release it must not have.
      for (final integration
          in options.integrations.whereType<LoadReleaseIntegration>()) {
        options.removeIntegration(integration);
      }
    }
  }

  /// The identity of this launch, read from the platform.
  static Future<BuildIdentity> readIdentity() =>
      readBuildIdentity(isWeb: kIsWeb, platform: defaultTargetPlatform);
}
