#!/usr/bin/env node
// Seeds demo data into Firestore for screenshots / manual testing.
//
// Only the VIEWER needs a real Firebase Auth account: the app resolves names
// from `users/{uid}` documents, and the deployed rules let any signed-in user
// read every user document and every wishlist. The other people here are plain
// Firestore documents whose uids never authenticate.
//
// Usage (credentials are never stored in the repo):
//
//   cd scripts && npm ci
//   GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
//     npm run seed:demo -- --yes --viewer-uid <uid> [--viewer-name <name>]
//
//   # remove every demo document again (items included)
//   GOOGLE_APPLICATION_CREDENTIALS=... npm run seed:demo -- --yes --clean-only
//
// Everything written here has a `demo-` id. `--clean-only` deletes only those,
// so it is safe to run against production at any time.
//
// Writes go to the production Firestore. While the data exists, any signed-in
// user can read it (wishlists are enumerable by design — see AGENTS.md,
// "Authorization model"), so run `--clean-only` after capturing screenshots.

import { readFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const PROJECT_ID = 'wish-together-project';
const DEMO_PREFIX = 'demo-';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const value = (name, fallback = null) => {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1];
};

if (!flag('--yes')) {
  console.error(
    'Refusing to run without --yes (this writes to the production Firestore).',
  );
  process.exit(2);
}

const viewerUid = value('--viewer-uid');
const viewerName = value('--viewer-name', 'Alex');
const cleanOnly = flag('--clean-only');

if (!cleanOnly && !viewerUid) {
  console.error('Missing --viewer-uid <uid> (the account you sign in with).');
  process.exit(2);
}

const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credentialsPath) {
  console.error(
    'Set GOOGLE_APPLICATION_CREDENTIALS to a Firebase service-account JSON.',
  );
  process.exit(2);
}
const credentials = JSON.parse(readFileSync(credentialsPath, 'utf8'));
if (credentials.project_id !== PROJECT_ID) {
  console.error(
    `Refusing to run: "${credentialsPath}" belongs to project "${credentials.project_id}", expected "${PROJECT_ID}".`,
  );
  process.exit(2);
}

const app = initializeApp({
  credential: cert(credentials),
  projectId: PROJECT_ID,
});
const db = getFirestore(app);
db.settings({ ignoreUndefinedProperties: true });

// ---------------------------------------------------------------------------
// People. These are Firestore documents only — none of them ever signs in.
// ---------------------------------------------------------------------------
const PEOPLE = [
  ['sam', 'Sam'],
  ['priya', 'Priya'],
  ['jordan', 'Jordan'],
  ['mia', 'Mia'],
  ['theo', 'Theo'],
  ['nan', 'Nan'],
  ['rob', 'Rob'],
  ['elena', 'Elena'],
  ['chris', 'Chris'],
  ['dana', 'Dana'],
];

const uidOf = (key) => (key === 'VIEWER' ? viewerUid : `${DEMO_PREFIX}user-${key}`);
const nameOf = (key) =>
  key === 'VIEWER' ? viewerName : PEOPLE.find(([k]) => k === key)?.[1];

// ---------------------------------------------------------------------------
// Groups. Overlapping memberships are the point: the viewer is in all three,
// and people belong to more than one.
// ---------------------------------------------------------------------------
const GROUPS = [
  {
    key: 'family',
    name: 'Family',
    owner: 'VIEWER',
    members: ['VIEWER', 'sam', 'priya', 'nan', 'rob'],
  },
  {
    key: 'inlaws',
    name: 'In-laws',
    owner: 'jordan',
    members: ['VIEWER', 'jordan', 'mia', 'theo'],
  },
  {
    key: 'friends',
    name: 'Friends',
    owner: 'sam',
    members: ['VIEWER', 'sam', 'jordan', 'elena', 'chris', 'dana'],
  },
];

// ---------------------------------------------------------------------------
// Wishlists. `shared` lists appear on their group pages; a list can be in more
// than one group. Items carry every key the app writes, so a later in-app claim
// does not "add" a key and get denied by the rules.
// ---------------------------------------------------------------------------
const link = (slug) => `https://example.com/gift/${slug}`;

const WISHLISTS = [
  {
    key: 'sam-christmas',
    name: 'Christmas 2026',
    owner: 'sam',
    groups: ['family'],
    items: [
      ['Cozy wool blanket', 'The grey one from the shop on Main Street.', 'wool-blanket'],
      ['Pour-over coffee set', null, 'pour-over-set', 'priya'],
      ['Board game: Wingspan', 'The European expansion if they have it.', 'wingspan'],
      ['Garden secateurs', null, null],
      ['Noise-cancelling headphones', 'Over-ear, not earbuds.', 'anc-headphones', 'VIEWER'],
      ['Cast iron skillet', '12 inch.', 'cast-iron'],
      ['Running socks', 'Size medium.', null, 'nan'],
      ['Watercolour set', 'Anything with a decent brush.', 'watercolour'],
      ['Linen apron', null, null],
      ['Hardback cookbook', 'Anything by Ottolenghi.', 'cookbook'],
    ],
  },
  {
    key: 'priya-birthday',
    name: "Priya's Birthday",
    owner: 'priya',
    groups: ['family'],
    items: [
      ['Silk pillowcase', null, 'silk-pillowcase'],
      ['Ceramics class voucher', 'The studio near the park.', null],
      ['Kindle cover', 'The fabric one.', 'kindle-cover', 'sam'],
      ['Perfume: Fig', 'She tried it at the counter.', null],
      ['Yoga blocks', null, 'yoga-blocks'],
      ['Book: Piranesi', null, 'piranesi'],
      ['Tea sampler', 'Loose leaf only.', null],
      ['Wool socks', null, null],
    ],
  },
  {
    key: 'nan-kitchen',
    name: 'Garden & Kitchen',
    owner: 'nan',
    groups: ['family'],
    items: [
      ['Herb planter', 'Window box, not too heavy.', 'herb-planter'],
      ['Dough scraper', null, null],
      ['Gardening gloves', 'Small.', 'gloves'],
      ['Jam thermometer', null, 'jam-thermometer'],
      ['Bird feeder', 'Squirrel-proof if possible.', null],
      ['Tea towel set', null, 'tea-towels'],
      ['Seed tin', null, null],
    ],
  },
  {
    key: 'jordan-holiday',
    name: 'Holiday List',
    owner: 'jordan',
    groups: ['inlaws'],
    items: [
      ['Hiking trousers', '32 waist.', 'hiking-trousers', 'mia'],
      ['Travel mug', null, 'travel-mug'],
      ['Head torch', null, 'head-torch'],
      ['Map: Lake District', 'The waterproof one.', null, 'theo'],
      ['Merino base layer', 'Medium.', 'merino-base'],
      ['Dry bag', '20 litres.', null],
      ['Trail snacks', null, null],
      ['Sunglasses', null, 'sunglasses'],
    ],
  },
  {
    key: 'mia-birthday',
    name: "Mia's Birthday",
    owner: 'mia',
    groups: ['inlaws'],
    items: [
      ['Pottery wheel class', 'Beginner course.', null],
      ['Linen shirt', 'White, size 10.', 'linen-shirt'],
      ['Vinyl: Rumours', null, 'rumours-vinyl', 'jordan'],
      ['Desk lamp', 'Warm bulb.', 'desk-lamp'],
      ['Sketchbook', 'A4, landscape.', null],
      ['Water bottle', null, 'water-bottle'],
      ['Stationery set', null, null],
    ],
  },
  {
    key: 'theo-books',
    name: 'Books & Games',
    owner: 'theo',
    groups: ['inlaws', 'friends'],
    items: [
      ['Book: The Master and Margarita', null, 'master-margarita'],
      ['Book: Project Hail Mary', null, 'hail-mary'],
      ['Puzzle: 1000 pieces', 'Something with a map.', 'map-puzzle'],
      ['Dice tray', null, null],
      ['Book: A Brief History of Time', null, 'brief-history', 'VIEWER'],
      ['Card game: Codenames', null, 'codenames'],
      ['Reading light', 'Clip-on.', null],
      ['Chess set', 'Wooden, travel size.', 'chess-set'],
    ],
  },
  {
    key: 'elena-wedding',
    name: 'Wedding Registry',
    owner: 'elena',
    groups: ['friends'],
    items: [
      ['Le Creuset casserole', 'The 26cm round one.', 'le-creuset'],
      ['Wine glasses', 'Set of six.', 'wine-glasses'],
      ['Linen sheets', 'King.', null],
      ['Cheese board', null, 'cheese-board'],
      ['Stand mixer', 'Cream, if they have it.', 'stand-mixer', 'chris'],
      ['Serving platter', null, null],
      ['Espresso tamper', null, 'tamper'],
      ['Candlesticks', null, 'candlesticks'],
      ['Picnic blanket', null, null],
    ],
  },
  {
    key: 'chris-camping',
    name: 'Camping Gear',
    owner: 'chris',
    groups: ['friends'],
    items: [
      ['Two-person tent', 'Lightweight.', 'tent'],
      ['Sleeping mat', null, 'sleeping-mat'],
      ['Camp stove', null, null],
      ['Enamel mug', null, 'enamel-mug'],
      ['Head torch', null, 'head-torch-2'],
      ['Folding chair', null, null],
      ['Water filter', null, 'water-filter'],
    ],
  },
  {
    key: 'dana-office',
    name: 'Home Office',
    owner: 'dana',
    groups: ['friends', 'family'],
    items: [
      ['Monitor arm', 'Single, gas spring.', 'monitor-arm'],
      ['Desk mat', 'Large, dark.', 'desk-mat'],
      ['Keyboard', 'Low profile.', 'keyboard'],
      ['Webcam', null, 'webcam'],
      ['Plant pot', 'For the monstera.', null],
      ['Cable tray', null, null],
    ],
  },
  {
    key: 'viewer-list',
    name: `${viewerName}'s Wishlist`,
    owner: 'VIEWER',
    groups: ['family', 'inlaws'],
    items: [
      ['Chef knife', '8 inch, Japanese steel.', 'chef-knife'],
      ['Cookbook: Salt Fat Acid Heat', null, 'salt-fat-acid'],
      ['Record player', 'With a built-in preamp.', 'record-player', 'sam'],
      ['Wool overcoat', 'Charcoal, medium.', 'overcoat'],
      ['Espresso cups', 'Set of two.', 'espresso-cups'],
      ['Board game: Cascadia', null, 'cascadia', 'jordan'],
      ['Running shoes', 'Size 10.', 'running-shoes'],
      ['Tool roll', null, null],
      ['Garden trowel', null, null],
    ],
  },
];

const claimedAtFor = (hoursAgo) =>
  Timestamp.fromDate(new Date(Date.now() - hoursAgo * 3600 * 1000));

const chunk = (arr, size) =>
  Array.from({ length: Math.ceil(arr.length / size) }, (_, i) =>
    arr.slice(i * size, i * size + size),
  );

// ---------------------------------------------------------------------------
// Clean: remove only `demo-` documents (and their subcollections).
// ---------------------------------------------------------------------------
async function clean() {
  let removed = 0;
  for (const collection of ['wishlists', 'groups', 'users']) {
    const snap = await db.collection(collection).get();
    for (const doc of snap.docs) {
      if (!doc.id.startsWith(DEMO_PREFIX)) continue;
      await db.recursiveDelete(doc.ref);
      removed += 1;
    }
  }
  return removed;
}

// ---------------------------------------------------------------------------
// Seed.
// ---------------------------------------------------------------------------
async function seed() {
  const batchWrites = [];
  const counts = { users: 0, groups: 0, wishlists: 0, items: 0 };

  for (const [key, name] of PEOPLE) {
    batchWrites.push(
      db.collection('users').doc(uidOf(key)).set({ displayName: name }),
    );
    counts.users += 1;
  }

  // Make sure the viewer's own profile shows the expected name, without
  // touching any other field the real account may have.
  batchWrites.push(
    db
      .collection('users')
      .doc(viewerUid)
      .set({ displayName: viewerName }, { merge: true }),
  );
  counts.users += 1;

  for (const group of GROUPS) {
    batchWrites.push(
      db
        .collection('groups')
        .doc(`${DEMO_PREFIX}group-${group.key}`)
        .set({
          name: group.name,
          ownerId: uidOf(group.owner),
          members: group.members.map(uidOf),
        }),
    );
    counts.groups += 1;
  }

  let claimHours = 2;
  for (const wishlist of WISHLISTS) {
    const wishlistRef = db
      .collection('wishlists')
      .doc(`${DEMO_PREFIX}wishlist-${wishlist.key}`);

    batchWrites.push(
      wishlistRef.set({
        name: wishlist.name,
        ownerId: uidOf(wishlist.owner),
        sharedWithGroups: wishlist.groups.map(
          (g) => `${DEMO_PREFIX}group-${g}`,
        ),
      }),
    );
    counts.wishlists += 1;

    wishlist.items.forEach((item, index) => {
      const [name, description, slug, claimedBy] = item;
      batchWrites.push(
        wishlistRef
          .collection('items')
          .doc(`${DEMO_PREFIX}item-${wishlist.key}-${index + 1}`)
          .set({
            name,
            description: description ?? null,
            url: slug ? link(slug) : null,
            claimedBy: claimedBy ? uidOf(claimedBy) : null,
            claimedAt: claimedBy ? claimedAtFor(claimHours++) : null,
          }),
      );
      counts.items += 1;
    });
  }

  // Writes are independent; a small bounded pool keeps it quick without
  // hammering the API.
  for (const group of chunk(batchWrites, 40)) {
    await Promise.all(group);
  }

  return counts;
}

const removed = await clean();
console.log(`Removed ${removed} existing demo document(s).`);

if (!cleanOnly) {
  const counts = await seed();
  console.log(
    `Seeded ${counts.users} user docs, ${counts.groups} groups, ` +
      `${counts.wishlists} wishlists, ${counts.items} items.`,
  );
  console.log(
    `Viewer: ${viewerName} (${viewerUid}) — a member of ` +
      GROUPS.map((g) => `"${g.name}"`).join(', ') +
      '.',
  );
  console.log('Run with --clean-only when you are done capturing.');
}
