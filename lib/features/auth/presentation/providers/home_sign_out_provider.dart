import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/presentation/providers/home_providers.dart';

/// What the home page should do after a sign-out attempt.
enum HomeSignOutResult {
  /// The credential is gone; the router is taking the page away.
  signedOut,

  /// The attempt failed while the session stayed live. The reads were reopened.
  failedSessionLive,

  /// The attempt failed after the session was cleared. Nothing restarts.
  failedSessionCleared,

  /// Another attempt is already in flight; this tap was ignored.
  busy,
}

/// The home page's sign-out command.
///
/// It owns the invariant the page used to guard in its own `State`: close the
/// read gate, clear the credential, then restart only when the session stayed
/// live. The page keeps the snackbar.
final homeSignOutProvider = NotifierProvider<HomeSignOut, bool>(
  HomeSignOut.new,
  isAutoDispose: true,
);

class HomeSignOut extends Notifier<bool> {
  @override
  bool build() => false;

  Future<HomeSignOutResult> signOut() async {
    if (state) return HomeSignOutResult.busy;

    final session = ref.read(authSessionProvider);

    // The ordering is the whole invariant: closing the gate before
    // `await session.signOut()` cancels the three subscriptions synchronously,
    // so the credential is cleared with no home read attached. Reversing that
    // order reintroduces #81.
    ref.read(homeReadsEnabledProvider.notifier).close();

    // A plain read opens and closes a temporary listener; without this link the
    // notifier would be disposed while the sign-out is in flight.
    final link = ref.keepAlive();
    state = true;
    try {
      await session.signOut();
      return HomeSignOutResult.signedOut;
    } catch (error, stackTrace) {
      appLogOrNull?.error(error, stackTrace, code: 'sign-out-failed');
      if (session.currentUserId == null) {
        // The session was cleared before the failure: there is nothing left to
        // read, so the gate stays closed and the page keeps its loading state.
        return HomeSignOutResult.failedSessionCleared;
      }

      // The page may have left while the attempt was in flight, in which case
      // the gate was auto-disposed with it. Re-read the notifier: a fresh gate
      // already starts open, so this cannot touch a disposed one.
      ref.read(homeReadsEnabledProvider.notifier).open();
      return HomeSignOutResult.failedSessionLive;
    } finally {
      if (ref.mounted) state = false;
      link.close();
    }
  }
}
