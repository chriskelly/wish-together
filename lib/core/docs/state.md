# Screen state and providers

Scope: how a signed-in screen reads data and runs commands through Riverpod, the temporary
getIt bridge, the retry policy, and the test patterns. Read before adding a provider or
migrating another screen. Paths are relative to `lib/`, then to the repository root.

## Responsibility

- One owner per screen state: a `StreamProvider`/`FutureProvider` owns the read and its
  subscription; a `Notifier` owns mutating screen state.
- Presentation never imports `service_locator.dart`; it reaches getIt only through a bridge
  provider in `lib/core/providers.dart`.
- `application/` and `domain/` stay free of Flutter and Riverpod. Providers live in
  `lib/core/providers.dart` (bridge) and `lib/features/<feature>/presentation/providers/`.

## Key concepts

| Type | What it does here |
| ---- | ----------------- |
| `Provider` | A lazy value with no state. Used only for the getIt bridge and derived values (`currentUserIdProvider`). |
| `StreamProvider` / `FutureProvider` | Converts a stream/future to `AsyncValue` and owns the subscription. `isAutoDispose: true` disposes it when the page leaves. |
| `Notifier` | Mutable screen state with methods. `state` is the value; `ref.read(provider.notifier)` calls commands. |
| `AsyncValue` | `loading` / `data` / `error`. `.value` is nullable and **retains the previous value** during a reload or error, so a screen that must clear on error checks `hasError` first. |
| `ProviderScope` | Stores provider state. One root scope is created in `WishTogetherApp.build`; tests add a nested scope with `overrides`. |
| `ref.watch` / `ref.read` / `ref.listen` | Subscribe (rebuild), read once (callbacks), or react without rebuilding (snackbars, navigation). |

## Root policy

`WishTogetherApp.build` wraps `MaterialApp.router` in
`ProviderScope(retry: disableAutomaticRetry, child: ...)`. `disableAutomaticRetry` lives in
`lib/core/providers.dart` and returns `null` for every failure, so nothing is retried behind the
user's back. Every test scope and `ProviderContainer` passes the same function; a non-`Error`
failure would otherwise be retried ten times.

## The getIt bridge

`lib/core/providers.dart` exposes one `Provider` per collaborator the migrated screens need,
each resolving `getIt<T>()`. `itemRepositoryProvider` is a family that derives the sub-repository
from `wishlistRepositoryProvider.items(id)`; it does not resolve a second instance. The bridge is
temporary: constructor injection replaces it feature by feature, and the bridge is removed when
getIt leaves presentation.

## Reads and commands

- A read is `StreamProvider.family<T, String>(..., isAutoDispose: true)` named after the state.
  The family argument is the entity id. Watch it in the page and render the `AsyncValue` with
  `ListContentBuilder` (or the page's own loading/error branches). Do not call `ref.watch` inside
  an `entityWidgetBuilder`; that callback runs during a descendant's build.
- A command is a `Notifier<TState>` with one `busyItemId`-style field. Its methods call the use
  case and rethrow; it returns `false` when another action is already running. Side effects
  (dialog, snackbar, navigation) stay in the widget, and the handler checks `context.mounted`
  after every await.
- A command notifier is `isAutoDispose`. It calls `ref.keepAlive()` for the duration of the
  action, because a plain `read` opens and closes a temporary listener and the notifier would be
  disposed before a second tap. Actions are serialised page-wide, not per item.
- `currentUserIdProvider` is a one-shot snapshot of `AuthSession.currentUserId`, not a stream.
  Sign-out is the router's concern; `AuthSession.uidChanges` is the reactive identity.

## How it is tested

- Transitions: `ProviderContainer.test(retry: disableAutomaticRetry, overrides: [...])`. Hold a
  listener for the test's lifetime (`container.listen(provider, (_, _) {}, fireImmediately:
  true)` and `addTearDown(subscription.close)`) before awaiting an asynchronous provider or
  reading an auto-disposed notifier more than once.
- Widgets: `ProviderScope(retry: disableAutomaticRetry, overrides: [...])` around the page. No
  `getIt.registerSingleton` for a migrated page's collaborators.
- App-level overrides nest another `ProviderScope` around `WishTogetherApp`; the root scope
  still owns the production container.
- A subscription test counts listens and cancels on a broadcast stream: one listen per page
  lifetime, no re-listen after a rebuild, a cancel when the page leaves, and one new listen on
  re-entry.

## Add an async slice

1. Add a bridge provider in `lib/core/providers.dart` if the collaborator is not there.
2. Add `StreamProvider`/`FutureProvider.family` in the feature's `presentation/providers/`,
   `isAutoDispose: true`, named after the state.
3. Add a `Notifier` for commands; call use cases and rethrow, keep `busyItemId`, keep side
   effects in the widget.
4. Make the page a `ConsumerWidget` and render the `AsyncValue`; remove the old `State`.
5. Test transitions with `ProviderContainer.test`; test widgets with `ProviderScope(overrides:)`.

## Known exceptions

- `ItemActions.delete` calls `ItemRepository.delete` directly, as the page did before the
  migration. A `DeleteItemUseCase` does not exist yet; constructor injection for the wishlist
  feature is the place to close that gap.
- The delete guard serialises the write, not the confirmation dialog: two quick taps can open two
  dialogs, and only the write that is still in flight is ignored.
- A stream that completes without emitting leaves the list loading; Firestore `snapshots()` does
  not complete, so the app does not reach it.
