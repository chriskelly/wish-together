import 'package:package_info_plus/package_info_plus.dart';

/// Loads the running app's package metadata.
///
/// Injectable because the production implementation,
/// `PackageInfo.fromPlatform`, is a plugin call that cannot run in a unit test.
typedef PackageInfoLoader = Future<PackageInfo> Function();
