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

  /// How long startup waits for Remote Config before failing open.
  static const Duration defaultFetchTimeout = Duration(seconds: 3);

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

  /// Resolved lazily so constructing the service never touches the plugin; the
  /// only access happens inside [_fetchRemoteConfig]'s fail-open try block.
  FirebaseRemoteConfig get _remoteConfig =>
      _remoteConfigOverride ?? FirebaseRemoteConfig.instance;

  /// How long startup waits for Remote Config before failing open.
  final Duration fetchTimeout;

  /// Returns whether the running build must be blocked.
  ///
  /// Never throws and never blocks on uncertainty: a failed, timed-out, or
  /// unconfigured Remote Config leaves the gate inert.
  Future<UpdateDecision> check() async {
    if (!_gateApplies) {
      return const UpdateDecision.allowed();
    }

    final runningBuild = await _readRunningBuild();

    var minSupportedBuild = defaultMinSupportedBuild;
    var message = defaultUpdateMessage;
    var updateUrl = defaultUpdateUrl;

    if (!_bypassGate && await _fetchRemoteConfig()) {
      minSupportedBuild = _remoteConfig.getInt(minSupportedBuildKey);
      message = _remoteConfig.getString(updateMessageKey);
      updateUrl = _remoteConfig.getString(updateUrlKey);
    }

    return evaluateUpdate(
      runningBuild: runningBuild,
      minSupportedBuild: minSupportedBuild,
      message: message,
      updateUrl: updateUrl,
      bypass: _bypassGate,
    );
  }

  /// Fetches and activates Remote Config. Returns false when the server could
  /// not be reached in time; the caller then keeps the inert defaults.
  Future<bool> _fetchRemoteConfig() async {
    try {
      await _remoteConfig.setDefaults(const <String, dynamic>{
        minSupportedBuildKey: defaultMinSupportedBuild,
        updateMessageKey: '',
        updateUrlKey: defaultUpdateUrl,
      });
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: fetchTimeout,
          // The gate is a safety net: read the current policy on every launch
          // rather than accepting a stale cached value.
          minimumFetchInterval: Duration.zero,
        ),
      );
      await _remoteConfig.fetchAndActivate().timeout(fetchTimeout);
      return true;
    } catch (error) {
      // Fail open. Never lock a user out because the network failed.
      debugPrint(
        'App update gate: Remote Config unavailable, failing open: $error',
      );
      return false;
    }
  }

  Future<int?> _readRunningBuild() async {
    try {
      final packageInfo = await _loadPackageInfo();
      return int.tryParse(packageInfo.buildNumber);
    } catch (error) {
      debugPrint('App update gate: could not read the running build: $error');
      return null;
    }
  }
}
