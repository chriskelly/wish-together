# Data access

Scope: the repository base class, how a Firestore instance is chosen, and the
reporting contract every query honours. Read before adding a repository method
or a query. Paths are relative to `lib/core/` unless they start with `lib/` or
`test/`.

## `FirebaseRepository<T>`

Holds a `FirebaseFirestore instance` (injectable via the `firestore:` constructor argument
for tests), a `collectionPath` and its `collectionName` (the path's last segment).
Provides generic `streamAll`, `streamWhere(...)`, `streamOne`, `get`, `add`, `update`,
`updateData`, and `delete`. Subclasses implement `fromFirestore(DocumentSnapshot)` and
`toFirestore(T)`.

Every failed operation reports a `FirestoreErrorEvent` at this one seam, tagged with the
`collectionName` and the structured code, and then behaves exactly as before: a future
`rethrow`s the original error and a stream re-emits it through a transformer (not
`Stream.handleError`, which would make the stream forget the error and break
the error UI that `StreamListBuilder` and `ListContentBuilder` render).
Diagnostics never change the outcome. The guard covers the
model mapping too, so a `fromFirestore`/`toFirestore` `TypeError` is reported as a
`firestoreError` with no code — a client bug, not a backend code.

An override that cannot use a base method (a different query shape, a batch commit) must
call the **protected** `reportingFuture` / `reportingStream` instead of going to Firestore
directly. Deleting one of those wrappers is a silent failure — it was the violation that
made group-member loading (`streamUsersFromIds`) fail with no record at all. Report through
the repository that owns the collection, so `collectionName` names the right one:
`deleteWithItems` reports its item page read and batch commit through the `ItemRepository`.

In the running app the instance comes from `getIt<FirebaseFirestore>()`, created by
`createFirestoreInstance()`: `FirebaseFirestore.instance` when the build passes no
`WT_FIRESTORE_DATABASE`, otherwise `instanceFor(databaseId: ...)`. Tests inject a fake
directly and never construct the production instance.
**Direct construction still falls back to `FirebaseFirestore.instance`**; never do that in
app code — repositories are only constructed by `setupServiceLocator`.

## Invariants

- `FirebaseRepository.instance` is `late final`, assigned once in the constructor.
- `FirebaseRepository.collectionName` is what a diagnostics event reports; the path never is,
  because a nested path (`wishlists/<id>/items`) contains a document id.
- All repositories share the single `getIt<FirebaseFirestore>()` instance; a build that sets
  `WT_FIRESTORE_DATABASE` reaches exactly that database and no other.

## How it is tested

- `test/core/data/firebase_repository_test.dart` exercises the generic CRUD and stream
  methods against `FakeFirebaseFirestore` using a throwaway `TestModelRepository`.
- `test/core/firestore_target_test.dart` pins the database-id resolution: absent/blank means
  `(default)`, a named id is kept, and a malformed id throws instead of falling back to
  production. It also pins the define→stamp coupling and the default-vs-named instance
  selection; the staging workflow asserts the compiled bundle.
