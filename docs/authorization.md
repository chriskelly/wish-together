# Authorization

Scope: what `firestore.rules` allows, and how a change to it reaches production.
Read before changing a rule, a collection shape, or a query the app relies on.

`firestore.rules` (root) is the enforcement point for all data access. The app is written
to match it — it queries its own data and the data shared with a group the viewer belongs
to — but the app is not the security boundary; the rules are.

**Content writes are owner-only.** You can change a document's content or delete it only
if you own it. The owner is `ownerId` on a wishlist or a group, the parent wishlist's
`ownerId` for an item, and the `uid` on `users/{uid}`. Two exceptions exist:

- A group owner may hand the group to another member and remove themselves in the same
  write. That is the only way `ownerId` changes, and it exists so a group survives its
  owner deleting their account.
- On an item, the gate is: the parent wishlist's owner, or a reader of a wishlist that is
  shared with a group. A reader may add or remove only their own key in the item's `claims`
  map, whose value is a timestamp; their write may not change anything else. They cannot take
  over, remove or rewrite another person's claim. A finite `claimLimit` caps how many claims an
  item may hold (`0` is unlimited). The owner edits content and the limit only, and cannot
  lower a finite limit below the current number of claims. An item cannot be created already
  claimed, and create requires a non-negative integer limit. A stored item without `claimLimit`
  (written before the migration) is write-denied, including owner edits, until the migration adds
  it; rerunning the migration is the repair.

Group membership is the one other writable edge, and it is bounded to exactly that: a
signed-in user who has a group's id may add themselves to the group or remove themselves
from it, in a write that adds or removes precisely the caller. The owner cannot leave
their own group. Only the owner may rename a group.

**Reads are open to any signed-in user**, with two exceptions: listing groups is
members-only (the group's members array must contain the caller; a second, owner-pinned
list rule exists so `where('ownerId','==',uid)` stays provable — the owner is always a
member, so the listable set is unchanged), and items are readable only by their
wishlist's owner or when that wishlist is shared with a group. Note
that the second exception constrains *item* reads only. A wishlist document is readable by
any signed-in user, and that includes **listing the whole `wishlists` collection** — the
app only queries the viewer's own wishlists and the wishlists shared with a group they
belong to, but Firestore cannot express "shared with a group I belong to" as a provable
list query, so a crafted client can enumerate every wishlist and read the group ids in it.
Enumeration alone is enough for the items: an item is readable and claimable whenever its
parent wishlist is currently shared with at least one group, so a crafted client reaches the items
of every shared wishlist — no invite, group join or membership needed. Item reads and claim
writes are still gated on the parent wishlist, which is narrower than the wishlist read.
Because any reader of a shared wishlist can add their own claim, any signed-in user can claim
every unclaimed item in every shared wishlist. An owner's content edit no longer drops claims,
so a claim persists until that reader removes it (or the item is deleted). The cap is a count,
not a lock: the rules cannot serialise it, so two hostile clients racing for the last slot can
overshoot by one; the client transaction closes that for cooperating clients. The impact is an
extra gift, not data loss.

**Signing in is the only boundary the rules can see.** There is no allow-list, so "signed
in" means any account that can register, not "family". Treat anything readably open to a
signed-in user as public.

**Invariant — `users/{uid}` is a public document.** Every signed-in user can read every
user document; the group member list and the "Owned by <name>" label depend on that.
Rules cannot restrict fields on read, so **never add a non-public field to `users/{uid}`** —
a read of the document returns all of it. There is no owner-only rule under `users/{uid}`
today, so a sub-collection placed there is closed to everyone, including its owner: to keep
private fields, add that owner-only rule first, then store the fields there.

**Invariant — a wishlist document is public to signed-in users.** It is readable and
listable by every signed-in user, so never put a private field on it (a share token, a
private note) without accepting that it is public to signed-in users.

## How rules reach production

`.github/workflows/ci-rules.yml` runs the emulator suite in `rules_tests/` when a pull
request or a merge to `master` touches `firestore.rules`, `firebase.json`, anything under
`rules_tests/`, or that workflow file itself. On a merge it then runs the same suite and publishes the rules to
production. That suite is the **only** check in front of publication — a merge deploys, and
no other job inspects the rules — so a rules change needs its tests (see Commands in
`AGENTS.md`), and a case the suite does not cover is not covered at all.

To publish by hand:

```bash
firebase deploy --only firestore:rules --project wish-together-project
```

The deploy authenticates as the **Firebase Admin SDK service account**, which needs two
roles that Hosting deploys do not use: `roles/serviceusage.serviceUsageViewer`
(`firebase-tools` checks API enablement before deploying) and `roles/firebaserules.admin`
(compile and publish). Without either, the job **fails closed** and production keeps the
previous ruleset — it does not publish a partial or stale change silently.

To roll back, the Firebase console keeps a history of published rulesets (Firestore
Database → Rules): a previous ruleset can be cloned or restored, which publishes it
immediately.
