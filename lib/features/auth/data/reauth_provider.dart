/// The re-authentication flow used to confirm a signed-in user's identity.
enum ReauthProvider { google, apple, phone, unknown }

/// The fallback order when the session token does not name a provider we can
/// re-authenticate.
///
/// Phone first because a phone number is the one credential the app can always
/// re-verify; Apple last because it is iOS-only.
const List<String> _fallbackOrder = ['phone', 'google.com', 'apple.com'];

/// Picks the flow that confirms a signed-in user's identity.
///
/// Prefers [signInProvider] — the provider that issued the current ID token —
/// because Firebase can silently link Google and Apple onto one account (same
/// email), and only the token records which one this session used. Falls back to
/// the account's linked [providerIds] in a fixed order, skipping flows the
/// platform cannot run.
ReauthProvider preferredReauthProvider({
  required String? signInProvider,
  required List<String> providerIds,
  required bool isWeb,
}) {
  final fromToken = _reauthProviderFor(signInProvider, isWeb: isWeb);
  if (fromToken != ReauthProvider.unknown) {
    return fromToken;
  }

  for (final providerId in _fallbackOrder) {
    if (!providerIds.contains(providerId)) {
      continue;
    }
    final candidate = _reauthProviderFor(providerId, isWeb: isWeb);
    if (candidate != ReauthProvider.unknown) {
      return candidate;
    }
  }

  return ReauthProvider.unknown;
}

/// Maps a provider id to its re-authentication flow.
///
/// Sign in with Apple is offered on iOS only, so on the web it is not a usable
/// confirmation flow.
ReauthProvider _reauthProviderFor(String? providerId, {required bool isWeb}) {
  switch (providerId) {
    case 'google.com':
      return ReauthProvider.google;
    case 'apple.com':
      return isWeb ? ReauthProvider.unknown : ReauthProvider.apple;
    case 'phone':
      return ReauthProvider.phone;
    default:
      return ReauthProvider.unknown;
  }
}
