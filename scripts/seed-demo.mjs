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
const viewerName = value('--viewer-name', 'Shawn');
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
  ['sasha', 'Sasha'],
  ['blue', 'Blue'],
  ['tina', 'Tina'],
  ['solange', 'Solange'],
  ['kelly', 'Kelly'],
  ['michelle', 'Michelle'],
  ['gloria', 'Gloria'],
  ['angie', 'Angie'],
  ['ye', 'Ye'],
];

const uidOf = (key) => (key === 'VIEWER' ? viewerUid : `${DEMO_PREFIX}user-${key}`);
// ---------------------------------------------------------------------------
// Groups. Overlapping memberships are the point: the viewer is in all three,
// and people belong to more than one. This is the app's actual story --
// your family, your partner's family, and your friends.
// ---------------------------------------------------------------------------
const GROUPS = [
  {
    key: 'family',
    name: 'The Carters',
    owner: 'VIEWER',
    members: ['VIEWER', 'sasha', 'blue', 'gloria', 'tina'],
  },
  {
    key: 'knowles',
    name: 'The Knowles Family',
    owner: 'tina',
    members: ['VIEWER', 'sasha', 'tina', 'solange', 'angie', 'kelly'],
  },
  {
    key: 'crew',
    name: 'The Crew',
    owner: 'kelly',
    members: ['VIEWER', 'sasha', 'kelly', 'michelle', 'ye'],
  },
];

// ---------------------------------------------------------------------------
// Wishlists. `groups` lists appear on their group pages; a list can be in more
// than one group. Items carry every key the app writes, so a later in-app claim
// does not "add" a key and get denied by the rules.
//
// Item tuple: [name, description, linkSlug, claimedByKey]
// ---------------------------------------------------------------------------
const link = (slug) => `https://example.com/gift/${slug}`;

const WISHLISTS = [
  {
    key: 'sasha-birthday',
    name: "Sasha's Birthday",
    owner: 'sasha',
    groups: ['family', 'knowles'],
    items: [
      ['Vintage microphone', 'The brass one for the studio wall.', 'vintage-mic'],
      ['Silk robe', 'Emerald green, medium.', 'silk-robe'],
      ['Dance heels', 'Size 8, something stage-ready.', 'dance-heels', 'tina'],
      ['Art print: Basquiat', 'The one from the 1983 show.', 'basquiat-print'],
      ['Honey gift set', 'Local, raw, three jars.', 'honey-set'],
      ['Vocal warm-up book', null, 'vocal-book'],
      ['Perfume: oud', null, 'oud-perfume', 'VIEWER'],
      ['Candle: fig & cedar', null, 'candle-fig'],
      ['Vinyl: Renaissance', 'The limited pressing.', 'renaissance-vinyl'],
    ],
  },
  {
    // A list the viewer keeps for the twins, who are not on WishTogether. The
    // app supports this: the list is owned by the person who manages it, and is
    // named after the people it is for. It also gives the viewer a second list,
    // so their Home screen shows that one account can hold several.
    key: 'rumi-sir-birthday',
    name: "Rumi and Sir's Birthday",
    owner: 'VIEWER',
    groups: ['family', 'knowles'],
    items: [
      ['Balance bike', 'For Sir — the blue one.', 'balance-bike'],
      ['Balance bike (matching)', 'For Rumi — the pink one.', 'balance-bike-pink'],
      ['Art easel', 'One each, so they stop arguing over it.', 'easel', 'tina'],
      ['Wooden blocks', 'The big set.', 'blocks'],
      ['Picture books', 'Anything with animals.', 'picture-books', 'blue'],
      ['Swim vests', 'Two, age 7.', 'swim-vests'],
      ['Plush lion', 'For Rumi.', 'plush-lion'],
      ['Kids camera', 'Drop-proof.', 'kids-camera'],
    ],
  },
  {
    key: 'blue-birthday',
    name: "Blue's Birthday",
    owner: 'blue',
    groups: ['family'],
    items: [
      ['Art supplies', 'The big set of pastels.', 'pastels'],
      ['Ballet slippers', 'Size 1.', 'ballet-slippers', 'sasha'],
      ['Telescope', 'Beginner, for the roof.', 'telescope'],
      ['Story books', 'Anything with dragons.', 'story-books'],
      ['Bead kit', null, 'bead-kit'],
      ['Camera', 'Kids, drop-proof.', 'kids-camera'],
      ['Colouring book', null, null],
      ['Hair ribbons', 'The big satin ones.', 'hair-ribbons'],
    ],
  },
  {
    key: 'tina-kitchen',
    name: "Tina's Kitchen",
    owner: 'tina',
    groups: ['family', 'knowles'],
    items: [
      ['Le Creuset pot', 'The 26cm round one.', 'le-creuset'],
      ['Cast iron skillet', '12 inch.', 'cast-iron'],
      ['Herb planter', 'For the kitchen window.', 'herb-planter'],
      ['Stand mixer', 'Cream.', 'stand-mixer'],
      ['Tea towel set', null, 'tea-towels'],
      ['Cookbook: Jubilee', 'Anything by Toni Tipton-Martin.', 'jubilee-cookbook'],
      ['Jam thermometer', null, 'jam-thermometer'],
      ['Serving platter', null, 'platter'],
    ],
  },
  {
    key: 'solange-studio',
    name: "Solange's Studio",
    owner: 'solange',
    groups: ['knowles'],
    items: [
      ['Film camera', '35mm, fully manual.', 'film-camera'],
      ['Sketchbooks', 'A3, heavy paper.', 'sketchbooks'],
      ['Vinyl: A Seat at the Table', null, 'seat-at-table'],
      ['Ceramics class', 'Six weeks, beginner.', 'ceramics-class'],
      ['Studio lamp', 'Warm, adjustable.', 'studio-lamp'],
      ['Silk shirt', 'Oversized, black.', 'silk-shirt'],
      ['Art book: Kerry James Marshall', null, 'kjm-book'],
      ['Incense set', null, null],
    ],
  },
  {
    key: 'kelly-list',
    name: "Kelly's List",
    owner: 'kelly',
    groups: ['knowles', 'crew'],
    items: [
      ['Yoga mat', 'Thick, non-slip.', 'yoga-mat'],
      ['Running shoes', 'Size 7.', 'running-shoes'],
      ['Journal', 'Lined, A5.', 'journal'],
      ['Book: The Vanishing Half', null, 'vanishing-half'],
      ['Water bottle', 'Insulated, 1L.', 'water-bottle'],
      ['Resistance bands', null, 'resistance-bands', 'michelle'],
      ['Silk pillowcase', null, 'silk-pillowcase'],
      ['Perfume: neroli', null, null],
    ],
  },
  {
    key: 'michelle-list',
    name: "Michelle's List",
    owner: 'michelle',
    groups: ['crew'],
    items: [
      ['Theatre tickets', 'Anything at the Almeida.', null],
      ['Book: Tomorrow x3', null, 'tomorrow-x3'],
      ['Tea set', 'A proper pot and cups.', 'tea-set'],
      ['Sheet music stand', null, 'music-stand'],
      ['Cashmere scarf', 'Navy.', 'cashmere-scarf'],
      ['Vinyl: Destiny Fulfilled', null, 'destiny-fulfilled'],
      ['Desk lamp', null, 'desk-lamp'],
    ],
  },
  {
    key: 'gloria-garden',
    name: "Gloria's Garden",
    owner: 'gloria',
    groups: ['family'],
    items: [
      ['Rose bushes', 'Two, pale pink.', 'rose-bushes'],
      ['Garden gloves', 'Small.', 'gloves'],
      ['Bird feeder', 'Squirrel-proof.', 'bird-feeder'],
      ['Seed tin', null, 'seed-tin'],
      ['Garden bench', 'Wooden, two-seater.', 'garden-bench'],
      ['Watering can', 'Brass.', 'watering-can'],
      ['Pruning shears', null, 'shears'],
    ],
  },
  {
    key: 'angie-travel',
    name: "Angie's Travel Kit",
    owner: 'angie',
    groups: ['knowles'],
    items: [
      ['Travel wallet', 'Passport and cards.', 'travel-wallet'],
      ['Packing cubes', 'Set of four.', 'packing-cubes'],
      ['Noise-cancelling headphones', 'Over-ear, not earbuds.', 'anc-headphones', 'VIEWER'],
      ['Neck pillow', null, 'neck-pillow'],
      ['Universal adapter', null, 'adapter'],
      ['Luggage scale', null, null],
      ['Weekender bag', 'Canvas, tan.', 'weekender'],
    ],
  },
  {
    key: 'ye-studio',
    name: "Ye's Studio",
    owner: 'ye',
    groups: ['crew'],
    items: [
      ['Sketchbook', 'A4, landscape.', 'sketchbook'],
      ['Architecture book: Neutra', null, 'neutra-book'],
      ['Studio lamp', 'Daylight, adjustable.', 'studio-lamp-2'],
      ['Vinyl: The College Dropout', null, 'college-dropout'],
      ['Sneakers', 'Size 10, white.', 'sneakers'],
      ['Desk chair', 'Something mid-century.', null],
      ['Headphones', null, 'headphones'],
    ],
  },
  {
    key: 'viewer-birthday',
    name: `${viewerName}'s Birthday`,
    owner: 'VIEWER',
    groups: ['family', 'crew'],
    items: [
      ['Vintage watch', 'The 1960s one from the auction.', 'vintage-watch'],
      ['Art book: Basquiat', null, 'basquiat-book', 'sasha'],
      ['Vinyl: Reasonable Doubt', 'The reissue.', 'reasonable-doubt'],
      ['Cashmere overcoat', 'Charcoal, medium.', 'overcoat'],
      ['Espresso machine', 'The one with the pressure gauge.', 'espresso-machine'],
      ['Studio headphones', null, 'studio-headphones', 'blue'],
      ['Cufflinks', 'Silver, simple.', 'cufflinks'],
      ['Chess set', 'Wooden, travel size.', 'chess-set'],
      ['Running shoes', 'Size 10.', 'running-shoes-2'],
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
