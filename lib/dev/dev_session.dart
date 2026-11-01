import 'package:wishtogether/features/auth/domain/auth_session.dart';

/// The signed-in identity of a development session.
///
/// It implements [AuthSession] and nothing else: there is no sign-in flow, no
/// provider plumbing and no Firebase behind it. The shell only ever resolves
/// the interface, which is what makes this class the whole of the dev session's
/// auth.
class DevAuthSession implements AuthSession {
  const DevAuthSession(this.uid);

  /// The uid the fixture's documents are addressed by.
  final String uid;

  @override
  String? get currentUserId => uid;

  /// A dev session has no provider, so there is no email or phone number to
  /// report; the fixture supplies everything through `users/{uid}` instead.
  @override
  String? get currentUserEmail => null;

  @override
  String? get currentUserPhoneNumber => null;

  @override
  List<String> get providerIds => const <String>[];

  /// Never emits: routing reads [currentUserId], and the fixture's identity
  /// does not change during a session (a reload re-seeds it).
  @override
  Stream<String?> get uidChanges => const Stream<String?>.empty();

  /// Does nothing.
  ///
  /// The dev shell hides the sign-out control: there is no sign-in flow behind
  /// this session to return to. If a call reaches here anyway, staying signed
  /// in keeps the app usable instead of leaving it on a page it cannot build.
  @override
  Future<void> signOut() async {}

  /// Deletion needs a real account behind the session.
  @override
  bool get supportsAccountDeletion => false;

  @override
  bool get supportsSignOut => false;
}
