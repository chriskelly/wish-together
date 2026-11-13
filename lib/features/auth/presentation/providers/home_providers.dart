import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

/// Whether the home page's three reads may be attached.
///
/// Sign-out closes it before `AuthSession.signOut()`, so Riverpod cancels the
/// streams in the same turn; a failure that leaves the session live opens it
/// again. It is auto-disposed with the page, so a later home lifetime starts
/// enabled rather than inheriting a closed gate.
final homeReadsEnabledProvider = NotifierProvider<HomeReadsEnabled, bool>(
  HomeReadsEnabled.new,
  isAutoDispose: true,
);

class HomeReadsEnabled extends Notifier<bool> {
  @override
  bool build() => true;

  void close() => state = false;

  void open() => state = true;
}

/// The signed-in user's document, or null when the stream ended without one.
final homeUserProvider = StreamProvider.family<User?, String>((ref, userId) {
  if (!ref.watch(homeReadsEnabledProvider)) {
    // A closed read must not touch a repository: the credential may already
    // be gone. The value is never rendered while the gate is closed.
    return Stream<User?>.value(null);
  }
  return _withFallbackOnEmpty<User?>(
    // A plain Stream<User> fails transform's covariant argument check; the cast
    // makes the runtime type match the transformer's User? parameter.
    ref.watch(userRepositoryProvider).streamOne(userId).cast<User?>(),
    null,
  );
}, isAutoDispose: true);

/// The user's own wishlists.
final homeWishlistsProvider = StreamProvider.family<List<Wishlist>, String>((
  ref,
  userId,
) {
  if (!ref.watch(homeReadsEnabledProvider)) {
    return Stream.value(const <Wishlist>[]);
  }
  return _withFallbackOnEmpty<List<Wishlist>>(
    ref
        .watch(wishlistRepositoryProvider)
        .streamWhere('ownerId', isEqualTo: userId),
    const <Wishlist>[],
  );
}, isAutoDispose: true);

/// The groups the user belongs to.
final homeGroupsProvider = StreamProvider.family<List<Group>, String>((
  ref,
  userId,
) {
  if (!ref.watch(homeReadsEnabledProvider)) {
    return Stream.value(const <Group>[]);
  }
  return _withFallbackOnEmpty<List<Group>>(
    ref
        .watch(groupRepositoryProvider)
        .streamWhere('members', arrayContains: userId),
    const <Group>[],
  );
}, isAutoDispose: true);

/// Emits [fallback] when [source] ends without a value or an error.
///
/// A `StreamProvider` whose stream completes without emitting stays in its
/// loading state forever, which would turn the home page's "the profile stream
/// ended with no document" branch into an endless spinner. Errors pass through
/// unchanged, and an error followed by done stays an error.
Stream<T> _withFallbackOnEmpty<T>(Stream<T> source, T fallback) =>
    source.transform(_FallbackOnEmpty<T>(fallback));

class _FallbackOnEmpty<T> extends StreamTransformerBase<T, T> {
  const _FallbackOnEmpty(this.fallback);

  final T fallback;

  @override
  Stream<T> bind(Stream<T> stream) {
    // Per subscription: re-listening must re-evaluate whether anything arrived.
    var emitted = false;
    var failed = false;
    return stream.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (value, sink) {
          emitted = true;
          sink.add(value);
        },
        handleError: (error, stackTrace, sink) {
          failed = true;
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          if (!emitted && !failed) sink.add(fallback);
          sink.close();
        },
      ),
    );
  }
}
