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

// Reference helpers build a path from the caller's uid, so a case reads a
// document through the same contextual client it asserts with. `anonItemRef`
// is the unauthenticated counterpart.
const groupRef = (uid, groupId) => db(uid).collection('groups').doc(groupId);

const seedGroup = (
  store,
  groupId,
  { name = 'Group', ownerId = OWNER, members = [ownerId] } = {},
) => store.collection('groups').doc(groupId).set({ name, ownerId, members });

const wishlistRef = (uid, wishlistId) =>
  db(uid).collection('wishlists').doc(wishlistId);

const seedWishlist = (store, wishlistId, { sharedWithGroups = [] } = {}) =>
  store.collection('wishlists').doc(wishlistId).set({
    name: 'Wishlist',
    ownerId: OWNER,
    sharedWithGroups,
  });

const itemsRef = (uid, wishlistId) =>
  wishlistRef(uid, wishlistId).collection('items');

const itemRef = (uid, wishlistId, itemId) =>
  itemsRef(uid, wishlistId).doc(itemId);

const anonItemRef = (wishlistId, itemId) =>
  anonDb().collection('wishlists').doc(wishlistId).collection('items').doc(itemId);

const seedItem = (store, wishlistId, itemId, data = { name: 'Gift' }) =>
  store
    .collection('wishlists')
    .doc(wishlistId)
    .collection('items')
    .doc(itemId)
    .set(data);

// Most item cases need one item under one wishlist; this keeps that fixture in
// one place.
const seedWishlistWithItem = async (
  store,
  wishlistId,
  itemId,
  { sharedWithGroups = [], item = { name: 'Gift' } } = {},
) => {
  await seedWishlist(store, wishlistId, { sharedWithGroups });
  await seedItem(store, wishlistId, itemId, item);
};

// ── users ────────────────────────────────────────────────────────────────────
// A profile is readable by any signed-in user but writable only by its owner.

// Profile documents are keyed by uid, so each case uses its own uid-shaped id.
test('an owner reads and writes their own profile', async () => {
  const ref = db(OWNER).collection('users').doc(OWNER);

  await assertSucceeds(ref.set({ displayName: 'Owner' }));
  await assertSucceeds(ref.get());
});

test('another signed-in user reads a profile', async () => {
  const profileId = 'uid-profile-public';
  await seed((s) =>
    s.collection('users').doc(profileId).set({ displayName: 'Someone' }),
  );

  await assertSucceeds(db(OUTSIDER).collection('users').doc(profileId).get());
});

test('another user cannot write a profile', async () => {
  const profileId = 'uid-profile-protected';
  await seed((s) =>
    s.collection('users').doc(profileId).set({ displayName: 'Someone' }),
  );

  await assertFails(
    db(OUTSIDER).collection('users').doc(profileId).set({ displayName: 'Impostor' }),
  );
});

test('an unauthenticated visitor cannot read a profile', async () => {
  const profileId = 'uid-profile-guarded';
  await seed((s) =>
    s.collection('users').doc(profileId).set({ displayName: 'Someone' }),
  );

  await assertFails(anonDb().collection('users').doc(profileId).get());
});

// ── groups / reads ───────────────────────────────────────────────────────────
// Listing is allowed only for the caller's own groups — the ones they are a
// member of, or the ones they own; a single group is readable by any signed-in
// user so the invite page can preview it before the visitor joins.

test('a member lists their own groups', async () => {
  const groupId = 'group-mine';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Mine', members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(MEMBER).collection('groups').where('members', 'array-contains', MEMBER).get(),
  );
});

test('the owner can list the groups they own', async () => {
  const groupId = 'group-owned';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Owned', members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    db(OWNER).collection('groups').where('ownerId', '==', OWNER).get(),
  );
});

test("a user cannot list another user's groups", async () => {
  const groupId = 'group-owned-elsewhere';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Owned', members: [OWNER, MEMBER] }),
  );

  await assertFails(
    db(MEMBER).collection('groups').where('ownerId', '==', OWNER).get(),
  );
});

test('a non-member cannot list a group they are not in', async () => {
  const groupId = 'group-hidden';
  await seed((s) => seedGroup(s, groupId, { name: 'Hidden', members: [OWNER] }));

  await assertFails(
    db(OUTSIDER)
      .collection('groups')
      .where('members', 'array-contains', OWNER)
      .get(),
  );
});

test('any signed-in user can get a group by its id', async () => {
  const groupId = 'group-preview';
  await seed((s) => seedGroup(s, groupId, { name: 'Preview', members: [OWNER] }));

  await assertSucceeds(groupRef(OUTSIDER, groupId).get());
});

// ── groups / writes ──────────────────────────────────────────────────────────
// Membership changes are incremental: a caller may add or remove only
// themselves, and only the owner may rename or delete.

test('the owner creates a group naming themselves owner and sole member', async () => {
  await assertSucceeds(
    groupRef(OWNER, 'group-create').set({
      name: 'New',
      ownerId: OWNER,
      members: [OWNER],
    }),
  );
});

test('creating a group that names a different owner is denied', async () => {
  await assertFails(
    groupRef(OWNER, 'group-create-other').set({
      name: 'New',
      ownerId: OUTSIDER,
      members: [OWNER],
    }),
  );
});

test('a group cannot be created that already includes another member', async () => {
  await assertFails(
    groupRef(OWNER, 'group-create-extra-member').set({
      name: 'New',
      ownerId: OWNER,
      members: [OWNER, MEMBER],
    }),
  );
});

test('the owner renames the group', async () => {
  const groupId = 'group-rename';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Old', members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(groupRef(OWNER, groupId).update({ name: 'New' }));
});

test('the owner renames the group by writing its whole map', async () => {
  const groupId = 'group-rename-map';
  const contents = { name: 'Old', ownerId: OWNER, members: [OWNER, MEMBER] };
  await seed((s) => seedGroup(s, groupId, contents));

  await assertSucceeds(
    groupRef(OWNER, groupId).update({ ...contents, name: 'New' }),
  );
});

test('a non-owner cannot rename the group', async () => {
  const groupId = 'group-rename-denied';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Old', members: [OWNER, MEMBER] }),
  );

  await assertFails(groupRef(MEMBER, groupId).update({ name: 'New' }));
});

test('a signed-in user joins a group by adding only themselves', async () => {
  const groupId = 'group-join';
  const members = [OWNER, MEMBER];
  await seed((s) => seedGroup(s, groupId, { name: 'Join', members: [OWNER] }));

  await assertSucceeds(groupRef(MEMBER, groupId).update({ members }));
});

test('a joiner cannot add themselves and another uid in one write', async () => {
  const groupId = 'group-join-two';
  const members = [OWNER, MEMBER, OUTSIDER];
  await seed((s) => seedGroup(s, groupId, { name: 'Join', members: [OWNER] }));

  await assertFails(groupRef(MEMBER, groupId).update({ members }));
});

test('joining a group with a different uid is denied', async () => {
  const groupId = 'group-join-other';
  const members = [OWNER, OUTSIDER];
  await seed((s) => seedGroup(s, groupId, { name: 'Join', members: [OWNER] }));

  await assertFails(groupRef(MEMBER, groupId).update({ members }));
});

test('a signed-in user joins a group by adding themselves with arrayUnion', async () => {
  const groupId = 'group-join-union';
  await seed((s) => seedGroup(s, groupId, { name: 'Join', members: [OWNER] }));

  await assertSucceeds(
    groupRef(MEMBER, groupId).update({ members: arrayUnion(MEMBER) }),
  );
});

test('joining a group with an arrayUnion of a different uid is denied', async () => {
  const groupId = 'group-join-union-other';
  const memberId = OUTSIDER;
  await seed((s) => seedGroup(s, groupId, { name: 'Join', members: [OWNER] }));

  await assertFails(
    groupRef(MEMBER, groupId).update({ members: arrayUnion(memberId) }),
  );
});

test('a member leaves a group by removing themselves with arrayRemove', async () => {
  const groupId = 'group-leave-remove';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Leave', members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    groupRef(MEMBER, groupId).update({ members: arrayRemove(MEMBER) }),
  );
});

test('a member leaves the group by removing only themselves', async () => {
  const groupId = 'group-leave';
  const members = [OWNER];
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Leave', members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(groupRef(MEMBER, groupId).update({ members }));
});

test('a member cannot remove another member in the same write that removes them', async () => {
  const groupId = 'group-leave-other';
  const members = [OWNER];
  await seed((s) =>
    seedGroup(s, groupId, {
      name: 'Leave',
      members: [OWNER, MEMBER, OUTSIDER],
    }),
  );

  await assertFails(groupRef(MEMBER, groupId).update({ members }));
});

test('the owner cannot leave their own group', async () => {
  const groupId = 'group-owner-leave';
  const members = [MEMBER];
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Leave', members: [OWNER, MEMBER] }),
  );

  await assertFails(groupRef(OWNER, groupId).update({ members }));
});

test('a non-owner cannot delete the group', async () => {
  const groupId = 'group-delete-denied';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Keep', members: [OWNER, MEMBER] }),
  );

  await assertFails(groupRef(MEMBER, groupId).delete());
});

test('the owner can delete their own group', async () => {
  const groupId = 'group-owner-delete';
  await seed((s) => seedGroup(s, groupId, { name: 'Delete', members: [OWNER] }));

  await assertSucceeds(groupRef(OWNER, groupId).delete());
});

// ── groups / owner transfer ──────────────────────────────────────────────────
// The owner may hand the group to a remaining member and leave it in one
// atomic update, so the group survives the owner deleting their account.

test('the owner transfers the group to a remaining member', async () => {
  const groupId = 'group-transfer';
  const members = [MEMBER];
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Transfer', members: [OWNER, MEMBER] }),
  );

  await assertSucceeds(
    groupRef(OWNER, groupId).update({ ownerId: MEMBER, members }),
  );
});

test('transferring the group to a non-member is denied', async () => {
  const groupId = 'group-transfer-outsider';
  const members = [MEMBER];
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Transfer', members: [OWNER, MEMBER] }),
  );

  await assertFails(
    groupRef(OWNER, groupId).update({ ownerId: OUTSIDER, members }),
  );
});

test('transferring while keeping the old owner in members is denied', async () => {
  const groupId = 'group-transfer-keep';
  const members = [OWNER, MEMBER];
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Transfer', members: [OWNER, MEMBER] }),
  );

  await assertFails(
    groupRef(OWNER, groupId).update({ ownerId: MEMBER, members }),
  );
});

test('a non-owner cannot make themselves the owner', async () => {
  const groupId = 'group-transfer-self';
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Transfer', members: [OWNER, MEMBER] }),
  );

  await assertFails(groupRef(MEMBER, groupId).update({ ownerId: MEMBER }));
});

test('the owner cannot relinquish the group while also dropping a third member', async () => {
  const groupId = 'group-transfer-drop';
  const members = [MEMBER];
  await seed((s) =>
    seedGroup(s, groupId, {
      name: 'Transfer',
      members: [OWNER, MEMBER, OUTSIDER],
    }),
  );

  await assertFails(
    groupRef(OWNER, groupId).update({ ownerId: MEMBER, members }),
  );
});

test('transferring ownership and renaming at once is denied', async () => {
  const groupId = 'group-transfer-rename';
  const members = [MEMBER];
  await seed((s) =>
    seedGroup(s, groupId, { name: 'Old', members: [OWNER, MEMBER] }),
  );

  await assertFails(
    groupRef(OWNER, groupId).update({ name: 'New', ownerId: MEMBER, members }),
  );
});

// ── wishlists ────────────────────────────────────────────────────────────────
// Content is owner-only, but reads — including listing — are open to any
// signed-in user. That open read is deliberate.

test('the owner creates a wishlist', async () => {
  await assertSucceeds(
    wishlistRef(OWNER, 'wishlist-create').set({
      name: 'Mine',
      ownerId: OWNER,
      sharedWithGroups: [],
    }),
  );
});

test('creating a wishlist already shared with a group is denied', async () => {
  await assertFails(
    wishlistRef(OWNER, 'wishlist-create-shared').set({
      name: 'Mine',
      ownerId: OWNER,
      sharedWithGroups: ['group-1'],
    }),
  );
});

test("a user cannot create a wishlist with someone else's ownerId", async () => {
  await assertFails(
    wishlistRef(OWNER, 'wishlist-create-other-owner').set({
      name: 'Mine',
      ownerId: OUTSIDER,
      sharedWithGroups: [],
    }),
  );
});

test('the owner renames the wishlist', async () => {
  const wishlistId = 'wishlist-rename';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertSucceeds(wishlistRef(OWNER, wishlistId).update({ name: 'New' }));
});

test('changing the wishlist owner is denied', async () => {
  const wishlistId = 'wishlist-owner-change';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertFails(wishlistRef(OWNER, wishlistId).update({ ownerId: OUTSIDER }));
});

test('a non-owner cannot update the wishlist', async () => {
  const wishlistId = 'wishlist-update-denied';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertFails(wishlistRef(OUTSIDER, wishlistId).update({ name: 'Theirs' }));
});

test('a non-owner cannot delete the wishlist', async () => {
  const wishlistId = 'wishlist-delete-denied';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertFails(wishlistRef(OUTSIDER, wishlistId).delete());
});

test('the owner shares a wishlist by writing the whole document', async () => {
  const wishlistId = 'wishlist-share';
  const groupId = 'group-1';
  const contents = { name: 'Wishlist', ownerId: OWNER };
  await seed((s) =>
    s
      .collection('wishlists')
      .doc(wishlistId)
      .set({ ...contents, sharedWithGroups: [] }),
  );

  await assertSucceeds(
    wishlistRef(OWNER, wishlistId).update({
      ...contents,
      sharedWithGroups: [groupId],
    }),
  );
});

test('the owner unshares a wishlist by writing the whole document', async () => {
  const wishlistId = 'wishlist-unshare';
  const groupId = 'group-1';
  const contents = { name: 'Wishlist', ownerId: OWNER };
  await seed((s) =>
    s
      .collection('wishlists')
      .doc(wishlistId)
      .set({ ...contents, sharedWithGroups: [groupId] }),
  );

  await assertSucceeds(
    wishlistRef(OWNER, wishlistId).update({
      ...contents,
      sharedWithGroups: [],
    }),
  );
});

test('the owner deletes a wishlist', async () => {
  const wishlistId = 'wishlist-owner-delete';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertSucceeds(wishlistRef(OWNER, wishlistId).delete());
});

test('an owner lists their own wishlists by ownerId', async () => {
  const wishlistId = 'wishlist-mine';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertSucceeds(
    db(OWNER).collection('wishlists').where('ownerId', '==', OWNER).get(),
  );
});

test('a member lists wishlists shared with their group', async () => {
  const wishlistId = 'wishlist-shared';
  const groupId = 'group-1';
  await seed((s) => seedWishlist(s, wishlistId, { sharedWithGroups: [groupId] }));

  await assertSucceeds(
    db(MEMBER)
      .collection('wishlists')
      .where('sharedWithGroups', 'array-contains', groupId)
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
  const wishlistId = 'wishlist-owner-crud';
  const itemId = 'item';
  await seed((s) => seedWishlist(s, wishlistId));

  const item = itemRef(OWNER, wishlistId, itemId);
  await assertSucceeds(item.set({ name: 'Gift' }));
  await assertSucceeds(item.update({ name: 'Renamed' }));
  await assertSucceeds(item.delete());
});

test('a reader of a shared wishlist lists and reads items', async () => {
  const wishlistId = 'wishlist-shared-read';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  const items = itemsRef(OUTSIDER, wishlistId);
  await assertSucceeds(items.get());
  await assertSucceeds(items.doc(itemId).get());
});

test('the owner lists the items of their own never-shared wishlist', async () => {
  const wishlistId = 'wishlist-owner-list';
  const itemId = 'item';
  await seed((s) => seedWishlistWithItem(s, wishlistId, itemId));

  await assertSucceeds(itemsRef(OWNER, wishlistId).get());
});

test('a non-reader cannot read or list items of a never-shared wishlist', async () => {
  const wishlistId = 'wishlist-private-read';
  const itemId = 'item';
  await seed((s) => seedWishlistWithItem(s, wishlistId, itemId));

  const items = itemsRef(OUTSIDER, wishlistId);
  await assertFails(items.get());
  await assertFails(items.doc(itemId).get());
});

test('a non-owner cannot create an item in a shared wishlist', async () => {
  const wishlistId = 'wishlist-item-create-denied';
  const itemId = 'item';
  await seed((s) =>
    seedWishlist(s, wishlistId, { sharedWithGroups: ['group-1'] }),
  );

  await assertFails(itemRef(OUTSIDER, wishlistId, itemId).set({ name: 'Gift' }));
});

test('a non-owner cannot delete an item in a shared wishlist', async () => {
  const wishlistId = 'wishlist-item-delete-denied';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertFails(itemRef(OUTSIDER, wishlistId, itemId).delete());
});

test('a reader claims an item', async () => {
  const wishlistId = 'wishlist-claim';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertSucceeds(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      claimedBy: OUTSIDER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('a reader cannot claim an item without a timestamp', async () => {
  const wishlistId = 'wishlist-claim-no-time';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertFails(
    itemRef(OUTSIDER, wishlistId, itemId).update({ claimedBy: OUTSIDER }),
  );
});

test('a reader cannot stamp an item they have not claimed', async () => {
  const wishlistId = 'wishlist-stamp-unclaimed';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertFails(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('a reader claims an item by writing its whole map', async () => {
  const wishlistId = 'wishlist-claim-map';
  const itemId = 'item';
  const contents = {
    name: 'Gift',
    description: 'Something they want',
    url: 'https://example.com/gift',
  };
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
      item: { ...contents, claimedBy: null, claimedAt: null },
    }),
  );

  await assertSucceeds(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      ...contents,
      claimedBy: OUTSIDER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('a reader unclaims their own item', async () => {
  const wishlistId = 'wishlist-unclaim';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
      item: { name: 'Gift', claimedBy: OUTSIDER, claimedAt: new Date() },
    }),
  );

  await assertSucceeds(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      claimedBy: null,
      claimedAt: null,
    }),
  );
});

test('a reader cannot change an item name, description or url', async () => {
  const wishlistId = 'wishlist-reader-edit';
  const nameItemId = 'item-name';
  const descriptionItemId = 'item-description';
  const urlItemId = 'item-url';
  await seed(async (s) => {
    await seedWishlist(s, wishlistId, { sharedWithGroups: ['group-1'] });
    await seedItem(s, wishlistId, nameItemId);
    await seedItem(s, wishlistId, descriptionItemId, {
      name: 'Gift',
      description: 'Original',
    });
    await seedItem(s, wishlistId, urlItemId, {
      name: 'Gift',
      url: 'https://example.com/gift',
    });
  });

  const items = itemsRef(OUTSIDER, wishlistId);
  await assertFails(items.doc(nameItemId).update({ name: 'Changed' }));
  await assertFails(items.doc(descriptionItemId).update({ description: 'Changed' }));
  await assertFails(
    items.doc(urlItemId).update({ url: 'https://example.com/other' }),
  );
});

test("a reader cannot take over another user's claim", async () => {
  const wishlistId = 'wishlist-takeover';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
      item: { name: 'Gift', claimedBy: MEMBER, claimedAt: new Date() },
    }),
  );

  await assertFails(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      claimedBy: OUTSIDER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('a claim with a non-timestamp claimedAt is denied', async () => {
  const wishlistId = 'wishlist-bad-claim-time';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertFails(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      claimedBy: OUTSIDER,
      claimedAt: 'yesterday',
    }),
  );
});

test('creating an item that is already claimed is denied', async () => {
  const wishlistId = 'wishlist-create-claimed';
  const itemId = 'item';
  await seed((s) => seedWishlist(s, wishlistId));

  await assertFails(
    itemRef(OWNER, wishlistId, itemId).set({
      name: 'Gift',
      claimedBy: OWNER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('an item under a never-shared wishlist cannot be claimed', async () => {
  const wishlistId = 'wishlist-private-claim';
  const itemId = 'item';
  await seed((s) => seedWishlistWithItem(s, wishlistId, itemId));

  await assertFails(
    itemRef(OUTSIDER, wishlistId, itemId).update({
      claimedBy: OUTSIDER,
      claimedAt: Timestamp.fromDate(new Date()),
    }),
  );
});

test('an unauthenticated visitor cannot read an item', async () => {
  const wishlistId = 'wishlist-anon-read';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertFails(anonItemRef(wishlistId, itemId).get());
});

test('an unauthenticated visitor cannot write to an item', async () => {
  const wishlistId = 'wishlist-anon-write';
  const itemId = 'item';
  await seed((s) =>
    seedWishlistWithItem(s, wishlistId, itemId, {
      sharedWithGroups: ['group-1'],
    }),
  );

  await assertFails(anonItemRef(wishlistId, itemId).update({ name: 'Changed' }));
});

// ── deny-by-default ──────────────────────────────────────────────────────────
// Paths with no matching rule stay closed.

test('reading a collection with no matching rule is denied', async () => {
  await seed((s) => s.collection('uncovered').doc('doc').set({ value: 1 }));

  await assertFails(db(OWNER).collection('uncovered').doc('doc').get());
});

test('writing a collection with no matching rule is denied', async () => {
  await seed((s) => s.collection('uncovered').doc('doc').set({ value: 1 }));

  await assertFails(db(OWNER).collection('uncovered').doc('doc').update({ value: 2 }));
});
