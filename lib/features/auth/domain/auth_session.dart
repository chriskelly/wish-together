/// The signed-in identity the app shell depends on.
///
/// The shell — the router, the signed-in pages and the use cases — needs to
/// know who is signed in, watch for that changing, sign out, and know whether
/// an account can be deleted from inside the app. It does not need Firebase, a
/// `GoogleSignIn` instance or a phone-verification flow, so this interface
/// carries none of them: an implementation that never touches Firebase can
/// stand in for the production one.
///
/// Sign-in, re-authentication and account deletion stay on the implementation
/// that owns them, because they need provider plumbing a session does not have.
abstract class AuthSession {
  /// The signed-in user's id, or `null` when nobody is signed in.
  String? get currentUserId;

  /// The email on the signed-in account, when the provider supplied one.
  String? get currentUserEmail;

  /// The phone number on the signed-in account, when the provider supplied one.
  String? get currentUserPhoneNumber;

  /// The provider ids linked to the signed-in account (`google.com`,
  /// `apple.com`, `phone`), and empty when nobody is signed in.
  ///
  /// The auth-transition record reports which provider produced the session,
  /// and a session that changes hands from one identity to another carries that
  /// provider list at the moment the change is observed.
  List<String> get providerIds;

  /// Emits the signed-in user's id on every auth transition and `null` on
  /// sign-out, starting with the current state.
  ///
  /// Carries ids rather than a Firebase user so an implementation without
  /// Firebase can produce the same stream. An implementation may also leave it
  /// unemitted, for a session that never changes.
  Stream<String?> get uidChanges;

  /// Signs the current user out. Does nothing when nobody is signed in.
  Future<void> signOut();

  /// Whether the app offers in-app account deletion for this session.
  ///
  /// Deletion re-authenticates against a real provider and deletes a real auth
  /// account. A session that cannot do that reports `false`, and the profile
  /// page hides the danger zone instead of offering a control that cannot work.
  bool get supportsAccountDeletion;
}
