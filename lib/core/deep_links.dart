import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, kIsWeb, TargetPlatform;
import 'package:wishtogether/core/app_urls.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';

/// The location a cold start opens: a queued Universal Link wins, then the
/// platform's initial route.
///
/// On web the platform default is the URL strategy's current route: a
/// configured `<base href>` prefix and the fragment are stripped, while the
/// query is kept (`/join?group=abc` stays as-is; a legacy `/#/login` link
/// lands on `/`). A blank default means home, matching the router's own
/// fallback.
String initialLocationFor({
  required String? pendingLocation,
  required String platformDefault,
}) {
  if (pendingLocation != null) {
    return pendingLocation;
  }
  final fallback = platformDefault.trim();
  return fallback.isEmpty ? '/' : fallback;
}

/// Delivers Universal Links to the router.
///
/// Listening starts in the constructor so a link received while Firebase or the
/// update gate is blocking is kept, then applied by [takePendingLocation] when
/// the app finally starts.
class DeepLinkService {
  DeepLinkService({Stream<Uri>? links, Set<String>? allowedHosts})
    : _allowedHosts = allowedHosts ?? universalLinkHostsFor(debug: kDebugMode) {
    (links ?? _platformLinks())?.listen(
      _onUri,
      onError: (Object error, StackTrace stackTrace) =>
          appLogOrNull?.error(error, stackTrace, code: 'link-stream-failed'),
    );
  }

  final Set<String> _allowedHosts;
  String? _pending;
  void Function(String location)? _navigate;

  static Stream<Uri>? _platformLinks() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    return AppLinks().uriLinkStream;
  }

  void _onUri(Uri uri) {
    final location = locationFromUniversalLink(
      uri,
      allowedHosts: _allowedHosts,
    );
    if (location == null) return;
    final navigate = _navigate;
    if (navigate == null) {
      _pending = location;
    } else {
      navigate(location);
    }
  }

  /// Returns and clears the most recent link seen before the router existed.
  String? takePendingLocation() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  /// Starts forwarding subsequent links. Flushes one received after
  /// [takePendingLocation] but before the router was attached.
  void attach(void Function(String location) navigate) {
    _navigate = navigate;
    final pending = takePendingLocation();
    if (pending != null) navigate(pending);
  }
}
