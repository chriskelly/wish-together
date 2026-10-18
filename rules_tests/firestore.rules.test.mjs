import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  arrayRemove,
  arrayUnion,
  setLogLevel,
  Timestamp,
} from 'firebase/firestore';

// Denied writes are expected here; keep the client from logging each one.
setLogLevel('silent');

// The rule set under test; the emulator loads this same file.
const RULES = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');

// A stable cast of uids, reused per case against a freshly seeded document.
const OWNER = 'uid-owner';
const MEMBER = 'uid-member';
const OUTSIDER = 'uid-outsider';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-wishtogether',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8085 },
  });
});

after(async () => {
  await env.cleanup();
});

// Every case seeds the documents it needs, so state never leaks between cases.
beforeEach(async () => {
  await env.clearFirestore();
});

const db = (uid) => env.authenticatedContext(uid).firestore();
const anonDb = () => env.unauthenticatedContext().firestore();

// Seed through a rules-disabled context: this is fixture setup, not the
// behaviour under test.
const seed = (fn) =>
  env.withSecurityRulesDisabled(async (context) => fn(context.firestore()));

const seedWishlist = (store, id, { ownerId = OWNER, sharedWithGroups = [] } = {}) =>
  store
    .collection('wishlists')
    .doc(id)
    .set({ name: 'Wishlist', ownerId, sharedWithGroups });

// ── users ────────────────────────────────────────────────────────────────────
// A profile is readable by any signed-in user but writable only by its owner.

// Profile documents are keyed by uid, so each case uses its own uid-shaped id.
test('an owner reads and writes their own profile', async () => {
  const ref = db(OWNER).collection('users').doc(OWNER);

  await assertSucceeds(ref.set({ displayName: 'Owner' }));
  await assertSucceeds(ref.get());
});

test('another signed-in user reads a profile', async () => {
  await seed((s) =>
    s.collection('users').doc('uid-profile-public').set({ displayName: 'Someone' }),
  );

  await assertSucceeds(
    db(OUTSIDER).collection('users').doc('uid-profile-public').get(),
  );
});

test('another user cannot write a profile', async () => {
  await seed((s) =>
    s
      .collection('users')
      .doc('uid-profile-protected')
      .set({ displayName: 'Someone' }),
  );

  await assertFails(
    db(OUTSIDER)
      .collection('users')
      .doc('uid-profile-protected')
      .set({ displayName: 'Impostor' }),
  );
});

test('an unauthenticated visitor cannot read a profile', async () => {
  await seed((s) =>
    s
      .collection('users')
      .doc('uid-profile-guarded')
      .set({ displayName: 'Someone' }),
  );

  await assertFails(
    anonDb().collection('users').doc('uid-profile-guarded').get(),
  );
});

// ── groups / reads ───────────────────────────────────────────────────────────
// Listing is members-only; a single group is readable by any signed-in user so
// the invite page can preview it before the visitor joins.

test('a member lists their own groups', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-mine')
      .set({ name: 'Mine', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(MEMBER).collection('groups').where('members', 'array-contains', MEMBER).get(),
  );
});

test('a non-member cannot list a group they are not in', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-hidden')
      .set({ name: 'Hidden', ownerId: OWNER, members: [OWNER] }),
  );

  await assertFails(
    db(OUTSIDER)
      .collection('groups')
      .where('members', 'array-contains', OWNER)
      .get(),
  );
});

test('any signed-in user can get a group by its id', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-preview')
      .set({ name: 'Preview', ownerId: OWNER, members: [OWNER] }),
  );

  await assertSucceeds(
    db(OUTSIDER).collection('groups').doc('group-preview').get(),
  );
});

// ── groups / writes ──────────────────────────────────────────────────────────
// Membership changes are incremental: a caller may add or remove only
// themselves, and only the owner may rename or delete.

test('the owner creates a group naming themselves owner and sole member', async () => {
  await assertSucceeds(
    db(OWNER)
      .collection('groups')
      .doc('group-create')
      .set({ name: 'New', ownerId: OWNER, members: [OWNER] }),
  );
});

test('creating a group that names a different owner is denied', async () => {
  await assertFails(
    db(OWNER)
      .collection('groups')
      .doc('group-create-other')
      .set({ name: 'New', ownerId: OUTSIDER, members: [OWNER] }),
  );
});

test('the owner renames the group', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-rename')
      .set({ name: 'Old', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(OWNER).collection('groups').doc('group-rename').update({ name: 'New' }),
  );
});

test('the owner renames the group by writing its whole map', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-rename-map')
      .set({ name: 'Old', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(OWNER).collection('groups').doc('group-rename-map').update({
      name: 'New',
      ownerId: OWNER,
      members: [OWNER, MEMBER],
    }),
  );
});

test('a non-owner cannot rename the group', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-rename-denied')
      .set({ name: 'Old', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(MEMBER)
      .collection('groups')
      .doc('group-rename-denied')
      .update({ name: 'New' }),
  );
});

test('a signed-in user joins a group by adding only themselves', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-join')
      .set({ name: 'Join', ownerId: OWNER, members: [OWNER] }),
  );

  await assertSucceeds(
    db(MEMBER)
      .collection('groups')
      .doc('group-join')
      .update({ members: [OWNER, MEMBER] }),
  );
});

test('joining a group with a different uid is denied', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-join-other')
      .set({ name: 'Join', ownerId: OWNER, members: [OWNER] }),
  );

  await assertFails(
    db(MEMBER)
      .collection('groups')
      .doc('group-join-other')
      .update({ members: [OWNER, OUTSIDER] }),
  );
});

test('a signed-in user joins a group by adding themselves with arrayUnion', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-join-union')
      .set({ name: 'Join', ownerId: OWNER, members: [OWNER] }),
  );

  await assertSucceeds(
    db(MEMBER)
      .collection('groups')
      .doc('group-join-union')
      .update({ members: arrayUnion(MEMBER) }),
  );
});

test('joining a group with an arrayUnion of a different uid is denied', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-join-union-other')
      .set({ name: 'Join', ownerId: OWNER, members: [OWNER] }),
  );

  await assertFails(
    db(MEMBER)
      .collection('groups')
      .doc('group-join-union-other')
      .update({ members: arrayUnion(OUTSIDER) }),
  );
});

test('a member leaves a group by removing themselves with arrayRemove', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-leave-remove')
      .set({ name: 'Leave', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(MEMBER)
      .collection('groups')
      .doc('group-leave-remove')
      .update({ members: arrayRemove(MEMBER) }),
  );
});

test('a member leaves the group by removing only themselves', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-leave')
      .set({ name: 'Leave', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(MEMBER).collection('groups').doc('group-leave').update({ members: [OWNER] }),
  );
});

test('the owner cannot leave their own group', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-owner-leave')
      .set({ name: 'Leave', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(OWNER)
      .collection('groups')
      .doc('group-owner-leave')
      .update({ members: [MEMBER] }),
  );
});

test('a non-owner cannot delete the group', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-delete-denied')
      .set({ name: 'Keep', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(db(MEMBER).collection('groups').doc('group-delete-denied').delete());
});

// ── groups / owner transfer ──────────────────────────────────────────────────
// The owner may hand the group to a remaining member and leave it in one
// atomic update, so the group survives the owner deleting their account.

test('the owner transfers the group to a remaining member', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-transfer')
      .set({ name: 'Transfer', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(OWNER)
      .collection('groups')
      .doc('group-transfer')
      .update({ ownerId: MEMBER, members: [MEMBER] }),
  );
});

test('transferring the group to a non-member is denied', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-transfer-outsider')
      .set({ name: 'Transfer', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(OWNER)
      .collection('groups')
      .doc('group-transfer-outsider')
      .update({ ownerId: OUTSIDER, members: [MEMBER] }),
  );
});

test('transferring while keeping the old owner in members is denied', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-transfer-keep')
      .set({ name: 'Transfer', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(OWNER)
      .collection('groups')
      .doc('group-transfer-keep')
      .update({ ownerId: MEMBER, members: [OWNER, MEMBER] }),
  );
});

test('a non-owner cannot make themselves the owner', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-transfer-self')
      .set({ name: 'Transfer', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(MEMBER)
      .collection('groups')
      .doc('group-transfer-self')
      .update({ ownerId: MEMBER }),
  );
});

test('transferring ownership and renaming at once is denied', async () => {
  await seed((s) =>
    s
      .collection('groups')
      .doc('group-transfer-rename')
      .set({ name: 'Old', ownerId: OWNER, members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(OWNER)
      .collection('groups')
      .doc('group-transfer-rename')
      .update({ name: 'New', ownerId: MEMBER, members: [MEMBER] }),
  );
});

// ── wishlists ────────────────────────────────────────────────────────────────
// Content is owner-only, but reads — including listing — are open to any
// signed-in user. That open read is deliberate.

test('the owner creates a wishlist', async () => {
  await assertSucceeds(
    db(OWNER)
      .collection('wishlists')
      .doc('wishlist-create')
      .set({ name: 'Mine', ownerId: OWNER, sharedWithGroups: [] }),
  );
});

test('creating a wishlist already shared with a group is denied', async () => {
  await assertFails(
    db(OWNER)
      .collection('wishlists')
      .doc('wishlist-create-shared')
      .set({ name: 'Mine', ownerId: OWNER, sharedWithGroups: ['group-1'] }),
  );
});

test('the owner renames the wishlist', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-rename'));

  await assertSucceeds(
    db(OWNER).collection('wishlists').doc('wishlist-rename').update({ name: 'New' }),
  );
});

test('changing the wishlist owner is denied', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-owner-change'));

  await assertFails(
    db(OWNER)
      .collection('wishlists')
      .doc('wishlist-owner-change')
      .update({ ownerId: OUTSIDER }),
  );
});

test('a non-owner cannot update the wishlist', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-update-denied'));

  await assertFails(
    db(OUTSIDER)
      .collection('wishlists')
      .doc('wishlist-update-denied')
      .update({ name: 'Theirs' }),
  );
});

test('a non-owner cannot delete the wishlist', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-delete-denied'));

  await assertFails(
    db(OUTSIDER).collection('wishlists').doc('wishlist-delete-denied').delete(),
  );
});

test('an owner lists their own wishlists by ownerId', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-mine'));

  await assertSucceeds(
    db(OWNER).collection('wishlists').where('ownerId', '==', OWNER).get(),
  );
});

test('a member lists wishlists shared with their group', async () => {
  await seed((s) =>
    seedWishlist(s, 'wishlist-shared', { sharedWithGroups: ['group-1'] }),
  );

  await assertSucceeds(
    db(MEMBER)
      .collection('wishlists')
      .where('sharedWithGroups', 'array-contains', 'group-1')
      .get(),
  );
});

test('any signed-in user can list every wishlist unfiltered', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-open'));

  await assertSucceeds(db(OUTSIDER).collection('wishlists').get());
});

test('an unauthenticated visitor cannot list wishlists', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-guarded'));

  await assertFails(anonDb().collection('wishlists').get());
});

// ── items ────────────────────────────────────────────────────────────────────
// Items are readable by the wishlist's owner or, once that wishlist is shared,
// by any signed-in user. Only the owner edits content; a reader may claim or
// unclaim only for themselves.

test('the owner creates, updates and deletes an item', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-owner-crud'));

  const items = db(OWNER)
    .collection('wishlists')
    .doc('wishlist-owner-crud')
    .collection('items');

  await assertSucceeds(items.doc('item').set({ name: 'Gift' }));
  await assertSucceeds(items.doc('item').update({ name: 'Renamed' }));
  await assertSucceeds(items.doc('item').delete());
});

test('a reader of a shared wishlist lists and reads items', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-shared-read', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-shared-read')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const items = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-shared-read')
    .collection('items');

  await assertSucceeds(items.get());
  await assertSucceeds(items.doc('item').get());
});

test('the owner lists the items of their own never-shared wishlist', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-owner-list', { sharedWithGroups: [] });
    await s
      .collection('wishlists')
      .doc('wishlist-owner-list')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  await assertSucceeds(
    db(OWNER)
      .collection('wishlists')
      .doc('wishlist-owner-list')
      .collection('items')
      .get(),
  );
});

test('a non-reader cannot read or list items of a never-shared wishlist', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-private-read', { sharedWithGroups: [] });
    await s
      .collection('wishlists')
      .doc('wishlist-private-read')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const items = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-private-read')
    .collection('items');

  await assertFails(items.get());
  await assertFails(items.doc('item').get());
});

test('a reader claims an item', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-claim', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-claim')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-claim')
    .collection('items')
    .doc('item');

  await assertSucceeds(
    item.update({ claimedBy: OUTSIDER, claimedAt: Timestamp.fromDate(new Date()) }),
  );
});

test('a reader cannot claim an item without a timestamp', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-claim-no-time', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-claim-no-time')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-claim-no-time')
    .collection('items')
    .doc('item');

  await assertFails(item.update({ claimedBy: OUTSIDER }));
});

test('a reader cannot stamp an item they have not claimed', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-stamp-unclaimed', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-stamp-unclaimed')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-stamp-unclaimed')
    .collection('items')
    .doc('item');

  await assertFails(item.update({ claimedAt: Timestamp.fromDate(new Date()) }));
});

test('a reader claims an item by writing its whole map', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-claim-map', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-claim-map')
      .collection('items')
      .doc('item')
      .set({
        name: 'Gift',
        description: 'Something they want',
        url: 'https://example.com/gift',
        claimedBy: null,
        claimedAt: null,
      });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-claim-map')
    .collection('items')
    .doc('item');

  await assertSucceeds(
    item.update({
      name: 'Gift',
      description: 'Something they want',
      url: 'https://example.com/gift',
      claimedBy: OUTSIDER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('a reader unclaims their own item', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-unclaim', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-unclaim')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift', claimedBy: OUTSIDER, claimedAt: new Date() });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-unclaim')
    .collection('items')
    .doc('item');

  await assertSucceeds(item.update({ claimedBy: null, claimedAt: null }));
});

test('a reader cannot change an item name, description or url', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-reader-edit', { sharedWithGroups: ['group-1'] });
    const items = s
      .collection('wishlists')
      .doc('wishlist-reader-edit')
      .collection('items');
    await items.doc('item-name').set({ name: 'Gift' });
    await items.doc('item-description').set({ name: 'Gift', description: 'Original' });
    await items
      .doc('item-url')
      .set({ name: 'Gift', url: 'https://example.com/gift' });
  });

  const items = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-reader-edit')
    .collection('items');

  await assertFails(items.doc('item-name').update({ name: 'Changed' }));
  await assertFails(items.doc('item-description').update({ description: 'Changed' }));
  await assertFails(
    items.doc('item-url').update({ url: 'https://example.com/other' }),
  );
});

test("a reader cannot take over another user's claim", async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-takeover', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-takeover')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift', claimedBy: MEMBER, claimedAt: new Date() });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-takeover')
    .collection('items')
    .doc('item');

  await assertFails(
    item.update({ claimedBy: OUTSIDER, claimedAt: Timestamp.fromDate(new Date()) }),
  );
});

test('a claim with a non-timestamp claimedAt is denied', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-bad-claim-time', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-bad-claim-time')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-bad-claim-time')
    .collection('items')
    .doc('item');

  await assertFails(item.update({ claimedBy: OUTSIDER, claimedAt: 'yesterday' }));
});

test('creating an item that is already claimed is denied', async () => {
  await seed((s) => seedWishlist(s, 'wishlist-create-claimed'));

  const item = db(OWNER)
    .collection('wishlists')
    .doc('wishlist-create-claimed')
    .collection('items')
    .doc('item');

  await assertFails(
    item.set({
      name: 'Gift',
      claimedBy: OWNER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('an item under a never-shared wishlist cannot be claimed', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-private-claim', { sharedWithGroups: [] });
    await s
      .collection('wishlists')
      .doc('wishlist-private-claim')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const item = db(OUTSIDER)
    .collection('wishlists')
    .doc('wishlist-private-claim')
    .collection('items')
    .doc('item');

  await assertFails(
    item.update({ claimedBy: OUTSIDER, claimedAt: Timestamp.fromDate(new Date()) }),
  );
});

test('an unauthenticated visitor cannot read an item', async () => {
  await seed(async (s) => {
    await seedWishlist(s, 'wishlist-anon-read', { sharedWithGroups: ['group-1'] });
    await s
      .collection('wishlists')
      .doc('wishlist-anon-read')
      .collection('items')
      .doc('item')
      .set({ name: 'Gift' });
  });

  const item = anonDb()
    .collection('wishlists')
    .doc('wishlist-anon-read')
    .collection('items')
    .doc('item');

  await assertFails(item.get());
});

// ── deny-by-default ──────────────────────────────────────────────────────────
// Paths with no matching rule stay closed.

test('reading a collection with no matching rule is denied', async () => {
  await seed((s) => s.collection('uncovered').doc('doc').set({ value: 1 }));

  await assertFails(db(OWNER).collection('uncovered').doc('doc').get());
});
