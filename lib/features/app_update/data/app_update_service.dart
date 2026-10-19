import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb, TargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

/// Loads the running app's package metadata.
///
/// Injectable because the production implementation, `PackageInfo.fromPlatform`,
/// is a plugin call that cannot run in a unit test.
typedef PackageInfoLoader = Future<PackageInfo> Function();

/// Reads the minimum supported build from Firebase Remote Config and compares
/// it with the running build.
///
/// This is a **policy nudge, not a security control**: a modified client can
/// bypass it. Its only job is to keep an outdated client off a server contract
/// it no longer understands.
class AppUpdateService {
  AppUpdateService({
    FirebaseRemoteConfig? remoteConfig,
    PackageInfoLoader? packageInfoLoader,
    bool? bypassGate,
    bool? gateApplies,
    this.fetchTimeout = defaultFetchTimeout,
    this.totalTimeout = defaultTotalTimeout,
  }) : _remoteConfigOverride = remoteConfig,
       _loadPackageInfo = packageInfoLoader ?? PackageInfo.fromPlatform,
       _bypassGate = bypassGate ?? _defaultBypass,
       _gateApplies = gateApplies ?? _defaultGateApplies;

  /// Compared with the running iOS `CFBundleVersion`.
  static const String minSupportedBuildKey = 'min_supported_build';

  /// Optional override for the blocking screen's message.
  static const String updateMessageKey = 'update_message';

  /// Optional App Store URL for the blocking screen's action.
  static const String updateUrlKey = 'update_url';

  /// The inert default: the gate does nothing until a maintainer raises it.
  static const int defaultMinSupportedBuild = 0;

  /// Hard-coded fallback for the App Store URL. Empty until the listing exists;
  /// set [updateUrlKey] in Remote Config once it does.
  static const String defaultUpdateUrl = '';

  /// How long the Remote Config SDK waits for a response.
  static const Duration defaultFetchTimeout = Duration(seconds: 3);

  /// Upper bound for the whole check, including the plugin calls that
  /// [defaultFetchTimeout] does not cover.
  static const Duration defaultTotalTimeout = Duration(seconds: 5);

  /// `--dart-define=WT_DISABLE_UPDATE_GATE=true` produces a maintainer build
  /// that never blocks. It is intentionally not reachable from the UI.
  static const bool _compileTimeBypass = bool.fromEnvironment(
    'WT_DISABLE_UPDATE_GATE',
  );

  static bool get _defaultBypass => kDebugMode || _compileTimeBypass;

  /// The gate compares against the iOS build number only. A web build number
  /// is not comparable, so the gate never applies there. Injectable for tests.
  static bool get _defaultGateApplies =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final FirebaseRemoteConfig? _remoteConfigOverride;
  final PackageInfoLoader _loadPackageInfo;
  final bool _bypassGate;
  final bool _gateApplies;

  /// The running build cannot change for the life of the process, so a
  /// successful read is reused across retries.
  int? _cachedRunningBuild;

  /// Resolved lazily so constructing the service never touches the plugin; the
  /// only access happens inside [check]'s fail-open bounds.
  FirebaseRemoteConfig get _remoteConfig =>
      _remoteConfigOverride ?? FirebaseRemoteConfig.instance;

  /// How long the Remote Config SDK waits for a response.
  final Duration fetchTimeout;

  /// Upper bound for the whole check, so a hung plugin cannot delay startup
  /// indefinitely. The gate runs before the first Flutter frame, so a slow
  /// check delays that frame up to this bound.
  final Duration totalTimeout;

  /// Returns whether the running build must be blocked.
  ///
  /// Never throws: any failure to determine the answer resolves to an allowed,
  /// inconclusive decision, so the app starts.
  Future<UpdateDecision> check() async {
    if (!_gateApplies || _bypassGate) {
      return const UpdateDecision.allowed(isConclusive: true);
    }
    try {
      return await _check().timeout(totalTimeout);
    } catch (error) {
      debugPrint('App update gate: check failed, failing open: $error');
      return const UpdateDecision.allowed();
    }
  }

  Future<UpdateDecision> _check() async {
    // Start both plugin calls together so a slow PackageInfo cannot eat the
    // Remote Config budget.
    final runningBuildFuture = _readRunningBuild();
    final valuesFuture = _fetchRemoteConfigValues();
    final runningBuild = await runningBuildFuture;
    final values = await valuesFuture;

    if (values == null) {
      return const UpdateDecision.allowed();
    }

    final decision = evaluateUpdate(
      runningBuild: runningBuild,
      minSupportedBuild: values.minSupportedBuild,
      message: values.message,
      updateUrl: values.updateUrl,
      conclusive: runningBuild != null,
    );

    if (decision.blockedForMissingUpdateUrl) {
      debugPrint(
        'App update gate: min_supported_build requires an update, but '
        'update_url is missing or is not a usable Apple App Store URL. '
        'Failing open; set update_url in Remote Config.',
      );
    }

    return decision;
  }

  Future<({int minSupportedBuild, String message, String updateUrl})?>
  _fetchRemoteConfigValues() async {
    try {
      await _remoteConfig.setDefaults(const <String, dynamic>{
        minSupportedBuildKey: defaultMinSupportedBuild,
        updateMessageKey: '',
        updateUrlKey: defaultUpdateUrl,
      });
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: fetchTimeout,
          // Read the current policy on every launch; the gate is a safety net.
          minimumFetchInterval: Duration.zero,
        ),
      );
      await _remoteConfig.fetchAndActivate().timeout(fetchTimeout);
      final minSupportedBuild = _remoteConfig.getInt(minSupportedBuildKey);
      final message = _remoteConfig.getString(updateMessageKey);
      final updateUrl = _remoteConfig.getString(updateUrlKey);
      _warnIfMinimumIsNotAnInteger();
      return (
        minSupportedBuild: minSupportedBuild,
        message: message,
        updateUrl: updateUrl,
      );
    } catch (error) {
      // Fail open. Never lock a user out because the network failed.
      debugPrint(
        'App update gate: Remote Config unavailable, failing open: $error',
      );
      return null;
    }
  }

  /// A string-typed value silently decodes to 0, which leaves the gate inert.
  /// Say so loudly instead of looking like the kill switch.
  void _warnIfMinimumIsNotAnInteger() {
    try {
      final value = _remoteConfig.getValue(minSupportedBuildKey);
      if (value.source == ValueSource.valueStatic) {
        return;
      }
      final raw = value.asString();
      if (raw.isEmpty || int.tryParse(raw) != null) {
        return;
      }
      debugPrint(
        'App update gate: min_supported_build is not an integer ("$raw"); '
        'the gate is inert.',
      );
    } catch (_) {
      // Diagnostics must never change the decision.
    }
  }

  Future<int?> _readRunningBuild() async {
    final cached = _cachedRunningBuild;
    if (cached != null) {
      return cached;
    }
    try {
      final packageInfo = await _loadPackageInfo();
      final build = int.tryParse(packageInfo.buildNumber);
      // Cache only a parsed build. A null result (loader failure or a
      // malformed build number) is re-read on the next check; the gate fails
      // open until a parse succeeds, so retrying is harmless.
      _cachedRunningBuild = build;
      return build;
    } catch (error) {
      debugPrint('App update gate: could not read the running build: $error');
      return null;
    }
  }
}
