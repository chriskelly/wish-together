/// Canonical public URLs and the rules for accepting an inbound Universal Link.
///
/// Pure Dart: the invite builder and the link mapper use these without pulling
/// in the deep-link plugin.
const String appHost = 'wishtogether.gift';
const String appOrigin = 'https://$appHost';
const String stagingHost = 'wish-together-staging.web.app';

/// Hosts a release build may open. Keep in sync with the Release entitlement.
const Set<String> releaseUniversalLinkHosts = {appHost};

/// Hosts a debug build may open. Keep in sync with the Debug entitlement.
const Set<String> debugUniversalLinkHosts = {appHost, stagingHost};

Set<String> universalLinkHostsFor({required bool debug}) =>
    debug ? debugUniversalLinkHosts : releaseUniversalLinkHosts;

/// Paths listed in the AASA. `/join` is exact; the id paths need one non-empty
/// segment (`/group/a/b` is not a route, so keep it out of the router).
bool isUniversalLinkPath(String path) {
  if (path == '/join') return true;
  return _isIdPath(path, '/group/') || _isIdPath(path, '/wishlist/');
}

bool _isIdPath(String path, String prefix) {
  if (!path.startsWith(prefix)) return false;
  final id = path.substring(prefix.length);
  return id.isNotEmpty && !id.contains('/');
}

/// Maps a Universal Link to the in-app location the router understands.
///
/// Returns null for anything outside the AASA contract, so the app keeps its
/// normal start location instead of routing an unexpected URL.
String? locationFromUniversalLink(
  Uri uri, {
  required Set<String> allowedHosts,
}) {
  if (uri.scheme != 'https') return null;
  if (!allowedHosts.contains(uri.host)) return null;
  if (!isUniversalLinkPath(uri.path)) return null;
  // `uri.query` is already percent-encoded, so concatenation preserves it.
  return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
}
