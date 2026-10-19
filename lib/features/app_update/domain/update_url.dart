/// Parses a Remote Config update URL, allowing only store-safe schemes.
///
/// Returns null when [raw] is empty, malformed, uses an unexpected scheme, or
/// has no host. `https` covers the App Store web listing; `itms-apps` covers
/// the native App Store deep link.
Uri? parseUpdateUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'itms-apps') {
    return null;
  }
  if (uri.host.isEmpty) {
    return null;
  }
  return uri;
}
