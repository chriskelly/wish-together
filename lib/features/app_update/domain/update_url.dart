/// Parses a Remote Config update URL, allowing only Apple App Store links.
///
/// Returns null when [raw] is empty, malformed, uses an unexpected scheme, or
/// does not target the App Store. A typo, shortener, or compromised Remote
/// Config must not send every blocked user to an arbitrary page.
Uri? parseUpdateUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'itms-apps') {
    return null;
  }
  if (!_storeHosts.contains(uri.host.toLowerCase())) {
    return null;
  }
  return uri;
}

/// `apps.apple.com` serves the web listing and `itms-apps` deep links;
/// `itunes.apple.com` is the legacy host that Apple still redirects.
const Set<String> _storeHosts = {'apps.apple.com', 'itunes.apple.com'};
