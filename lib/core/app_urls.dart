/// Canonical public URLs and the rules for accepting an inbound Universal Link.
///
/// Pure Dart: the router uses these without importing the deep-link plugin.
const String appOrigin = 'https://wishtogether.gift';
const String stagingHost = 'wish-together-staging.web.app';

/// Hosts a release build may open. Keep in sync with the Release entitlement.
const Set<String> releaseUniversalLinkHosts = {'wishtogether.gift'};

/// Hosts a debug build may open. Keep in sync with the Debug entitlement.
const Set<String> debugUniversalLinkHosts = {'wishtogether.gift', stagingHost};

Set<String> universalLinkHostsFor({required bool debug}) =>
    debug ? debugUniversalLinkHosts : releaseUniversalLinkHosts;

/// Paths listed in the AASA. `/join` is exact; the id paths need a non-empty id.
bool isUniversalLinkPath(String path) {
  if (path == '/join') return true;
  if (path.startsWith('/group/')) return path.length > '/group/'.length;
  if (path.startsWith('/wishlist/')) return path.length > '/wishlist/'.length;
  return false;
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
