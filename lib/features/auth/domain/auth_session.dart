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
  /// Read when a [uidChanges] event is observed, to name the provider that
  /// produced that session. An implementation must therefore install the new
  /// identity — [currentUserId] and this list — before it emits the change.
  List<String> get providerIds;

  /// Emits the signed-in user's id on every auth transition and `null` on
  /// sign-out.
  ///
  /// Carries ids rather than a Firebase user so an implementation without
  /// Firebase can produce it. The production session also emits the current
  /// state on subscription; an implementation may leave the stream unemitted,
  /// because routing reads [currentUserId] rather than waiting for an emission.
  Stream<String?> get uidChanges;

  /// Signs out of the session. Safe to call when nobody is signed in.
  Future<void> signOut();

  /// Whether the app offers in-app account deletion for this session.
  ///
  /// Deletion re-authenticates against a real provider and deletes a real auth
  /// account, so only the implementation that owns that account can report
  /// `true`. The profile page hides the danger zone for any other session
  /// instead of offering a control that cannot work.
  bool get supportsAccountDeletion;

  /// Whether the app shell offers a sign-out control for this session.
  ///
  /// Signing out returns the app to the sign-in screens, so it is only offered
  /// when a sign-in flow can be built behind the session — which needs the
  /// production service. A session without one reports `false`, and the shell
  /// hides the control rather than offering a button with nowhere to go.
  bool get supportsSignOut;
}
