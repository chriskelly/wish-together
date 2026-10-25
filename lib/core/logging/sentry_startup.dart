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
/// `staging` is the pre-merge host, which carries no release.
const String wtSentryEnvironment = String.fromEnvironment(
  'WT_SENTRY_ENVIRONMENT',
);

const String productionEnvironment = 'production';
const String stagingEnvironment = 'staging';
const String debugEnvironment = 'debug';

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
  return releaseMode ? productionEnvironment : debugEnvironment;
}

/// `wishtogether@<build>`, the release name of §4.4.
String releaseNameFor(String build) => 'wishtogether@$build';

/// `<platform>-<build>`, the dist name of §4.4.
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

/// The Sentry configuration of §4.5, as data.
///
/// Pure: it reads no globals, so the option values can be asserted in a VM
/// test. `main.dart` only decides whether to hand it to `SentryFlutter.init`.
class SentryStartup {
  const SentryStartup({
    required this.dsn,
    required this.environment,
    required this.identity,
  });

  factory SentryStartup.fromEnvironment({
    required BuildIdentity identity,
    required bool releaseMode,
    String dsn = wtSentryDsn,
    String environment = wtSentryEnvironment,
  }) => SentryStartup(
    dsn: dsn.trim(),
    environment: environmentFor(
      releaseMode: releaseMode,
      override: environment,
    ),
    identity: identity,
  );

  final String dsn;
  final String environment;
  final BuildIdentity identity;

  /// True for the pre-merge host, which deploys without a release.
  bool get isStaging => environment == stagingEnvironment;

  String? get release => isStaging ? null : releaseNameFor(identity.build);

  String? get dist =>
      isStaging ? null : distNameFor(identity.platform, identity.build);

  /// Applies the §4.5 values. Kept in one place so the contract is testable.
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
  }

  /// The identity of this launch, read from the platform.
  static Future<BuildIdentity> readIdentity() =>
      readBuildIdentity(isWeb: kIsWeb, platform: defaultTargetPlatform);
}
