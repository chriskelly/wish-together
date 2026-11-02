import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/scenario_items.dart';

/// The viewer of the `family` scenario.
const String familyViewerUid = 'fam-u1';

/// The viewer's own wishlist, reachable from home.
const String familyViewerWishlistId = 'fam-l11';

/// A wishlist somebody else owns and shares with two of the viewer's groups.
///
/// Nothing on home links to it: open `/wishlist/fam-l1` directly. Its claims are
/// visible because the viewer is a reader, which is the half of the spoiler
/// behaviour the viewer's own list cannot show.
const String familySharedWishlistId = 'fam-l1';

/// The date every claim in this scenario was made.
///
/// Fixed so a screenshot and a test agree; a fixture must not read the clock.
final Timestamp _claimedOn = Timestamp.fromDate(DateTime.utc(2026, 9, 20, 18));

/// The link an item points at, in the same shape the demo seed uses.
String _link(String slug) => 'https://example.com/gift/$slug';

/// Ten people, three overlapping groups, eleven wishlists and eighty-six items.
///
/// This is the multi-family dataset a real account looks like: the viewer
/// belongs to all three groups, other people belong to one or two, and the
/// wishlists cut across them. Someone else's list carries claims the viewer can
/// see; the viewer's own list carries claims the spoiler toggle hides by
/// default, so both halves of that behaviour have data behind them.
///
/// The item text, the group and sharing structure, the list sizes and the
/// placement of the nine claims follow `scripts/seed-demo.mjs`, which seeds the
/// same story into a real Firestore for screenshots. The cast is invented and
/// the few items that named a real person or title are renamed, so this is that
/// dataset's shape rather than a character-for-character copy. Item ids run in
/// one sequence (`fam-i01` to `fam-i86`) across the lists, so no two documents
/// in the scenario share an id; a lookup still needs the wishlist id, which is
/// the parent segment of the path.
Map<String, Map<String, dynamic>> _documents() {
  final documents = <String, Map<String, dynamic>>{
    'users/fam-u1': <String, dynamic>{'displayName': 'Ada Whitfield'},
    'users/fam-u2': <String, dynamic>{'displayName': 'Bea Whitfield'},
    'users/fam-u3': <String, dynamic>{'displayName': 'Cal Whitfield'},
    'users/fam-u4': <String, dynamic>{'displayName': 'Dara Bell'},
    'users/fam-u5': <String, dynamic>{'displayName': 'Eli Bell'},
    'users/fam-u6': <String, dynamic>{'displayName': 'Fran Whitfield'},
    'users/fam-u7': <String, dynamic>{'displayName': 'Gus Moreau'},
    'users/fam-u8': <String, dynamic>{'displayName': 'Hana Whitfield'},
    'users/fam-u9': <String, dynamic>{'displayName': 'Iris Moreau'},
    'users/fam-u10': <String, dynamic>{'displayName': 'Jo Tanaka'},
    'groups/fam-g1': <String, dynamic>{
      'name': 'The Whitfields',
      'ownerId': 'fam-u1',
      'members': <String>['fam-u1', 'fam-u2', 'fam-u3', 'fam-u4', 'fam-u6'],
    },
    'groups/fam-g2': <String, dynamic>{
      'name': 'The Bell Family',
      'ownerId': 'fam-u4',
      'members': <String>[
        'fam-u1',
        'fam-u2',
        'fam-u4',
        'fam-u5',
        'fam-u7',
        'fam-u9',
      ],
    },
    'groups/fam-g3': <String, dynamic>{
      'name': 'The Friday Crew',
      'ownerId': 'fam-u9',
      'members': <String>['fam-u1', 'fam-u2', 'fam-u9', 'fam-u8', 'fam-u10'],
    },
  };

  var itemNumber = 0;

  void wishlist(
    String id, {
    required String name,
    required String ownerId,
    required List<String> sharedWithGroups,
    required List<Map<String, dynamic>> items,
  }) {
    documents['wishlists/$id'] = <String, dynamic>{
      'name': name,
      'ownerId': ownerId,
      'sharedWithGroups': sharedWithGroups,
    };
    for (final item in items) {
      itemNumber += 1;
      final itemId = 'fam-i${itemNumber.toString().padLeft(2, '0')}';
      final path = 'wishlists/$id/items/$itemId';
      assert(
        !documents.containsKey(path),
        'the family fixture reuses the item id "$itemId" under $id',
      );
      documents[path] = item;
    }
  }

  wishlist(
    familySharedWishlistId,
    name: "Bea's Birthday",
    ownerId: 'fam-u2',
    sharedWithGroups: <String>['fam-g1', 'fam-g2'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Vintage microphone',
        description: 'The brass one for the studio wall.',
        url: _link('vintage-mic'),
      ),
      devItemFields(
        'Silk robe',
        description: 'Emerald green, medium.',
        url: _link('silk-robe'),
      ),
      devItemFields(
        'Dance heels',
        description: 'Size 8, something stage-ready.',
        url: _link('dance-heels'),
        claimedBy: 'fam-u4',
        claimedAt: _claimedOn,
      ),
      devItemFields(
        'Art print: abstract',
        description: 'The large one from the spring show.',
        url: _link('art-print'),
      ),
      devItemFields(
        'Honey gift set',
        description: 'Local, raw, three jars.',
        url: _link('honey-set'),
      ),
      devItemFields('Vocal warm-up book', url: _link('vocal-book')),
      devItemFields(
        'Perfume: oud',
        url: _link('oud-perfume'),
        claimedBy: familyViewerUid,
        claimedAt: _claimedOn,
      ),
      devItemFields('Candle: fig & cedar', url: _link('candle-fig')),
      devItemFields(
        'Vinyl: reissue',
        description: 'The limited pressing.',
        url: _link('vinyl-reissue'),
      ),
    ],
  );

  wishlist(
    'fam-l2',
    name: "The Twins' Birthday",
    ownerId: familyViewerUid,
    sharedWithGroups: <String>['fam-g1', 'fam-g2'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Balance bike',
        description: 'For the older twin, the blue one.',
        url: _link('balance-bike'),
      ),
      devItemFields(
        'Balance bike (matching)',
        description: 'For the younger twin, the pink one.',
        url: _link('balance-bike-pink'),
      ),
      devItemFields(
        'Art easel',
        description: 'One each, so they stop arguing over it.',
        url: _link('easel'),
        claimedBy: 'fam-u4',
        claimedAt: _claimedOn,
      ),
      devItemFields(
        'Wooden blocks',
        description: 'The big set.',
        url: _link('blocks'),
      ),
      devItemFields(
        'Picture books',
        description: 'Anything with animals.',
        url: _link('picture-books'),
        claimedBy: 'fam-u3',
        claimedAt: _claimedOn,
      ),
      devItemFields(
        'Swim vests',
        description: 'Two, age 7.',
        url: _link('swim-vests'),
      ),
      devItemFields(
        'Plush lion',
        description: 'For the younger twin.',
        url: _link('plush-lion'),
      ),
      devItemFields(
        'Kids camera',
        description: 'Drop-proof.',
        url: _link('kids-camera'),
      ),
    ],
  );

  wishlist(
    'fam-l3',
    name: "Cal's Birthday",
    ownerId: 'fam-u3',
    sharedWithGroups: <String>['fam-g1'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Art supplies',
        description: 'The big set of pastels.',
        url: _link('pastels'),
      ),
      devItemFields(
        'Ballet slippers',
        description: 'Size 1.',
        url: _link('ballet-slippers'),
        claimedBy: 'fam-u2',
        claimedAt: _claimedOn,
      ),
      devItemFields(
        'Telescope',
        description: 'Beginner, for the roof.',
        url: _link('telescope'),
      ),
      devItemFields(
        'Story books',
        description: 'Anything with dragons.',
        url: _link('story-books'),
      ),
      devItemFields('Bead kit', url: _link('bead-kit')),
      devItemFields(
        'Camera',
        description: 'Kids, drop-proof.',
        url: _link('kids-camera'),
      ),
      devItemFields('Colouring book'),
      devItemFields(
        'Hair ribbons',
        description: 'The big satin ones.',
        url: _link('hair-ribbons'),
      ),
    ],
  );

  wishlist(
    'fam-l4',
    name: "Dara's Kitchen",
    ownerId: 'fam-u4',
    sharedWithGroups: <String>['fam-g1', 'fam-g2'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Le Creuset pot',
        description: 'The 26cm round one.',
        url: _link('le-creuset'),
      ),
      devItemFields(
        'Cast iron skillet',
        description: '12 inch.',
        url: _link('cast-iron'),
      ),
      devItemFields(
        'Herb planter',
        description: 'For the kitchen window.',
        url: _link('herb-planter'),
      ),
      devItemFields(
        'Stand mixer',
        description: 'Cream.',
        url: _link('stand-mixer'),
      ),
      devItemFields('Tea towel set', url: _link('tea-towels')),
      devItemFields(
        'Cookbook: seasonal',
        description: 'Anything by the farm-to-table writers.',
        url: _link('seasonal-cookbook'),
      ),
      devItemFields('Jam thermometer', url: _link('jam-thermometer')),
      devItemFields('Serving platter', url: _link('platter')),
    ],
  );

  wishlist(
    'fam-l5',
    name: "Eli's Studio",
    ownerId: 'fam-u5',
    sharedWithGroups: <String>['fam-g2'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Film camera',
        description: '35mm, fully manual.',
        url: _link('film-camera'),
      ),
      devItemFields(
        'Sketchbooks',
        description: 'A3, heavy paper.',
        url: _link('sketchbooks'),
      ),
      devItemFields('Vinyl: live session', url: _link('live-session')),
      devItemFields(
        'Ceramics class',
        description: 'Six weeks, beginner.',
        url: _link('ceramics-class'),
      ),
      devItemFields(
        'Studio lamp',
        description: 'Warm, adjustable.',
        url: _link('studio-lamp'),
      ),
      devItemFields(
        'Silk shirt',
        description: 'Oversized, black.',
        url: _link('silk-shirt'),
      ),
      devItemFields('Art book: modernists', url: _link('modernists-book')),
      devItemFields('Incense set'),
    ],
  );

  wishlist(
    'fam-l6',
    name: "Iris's List",
    ownerId: 'fam-u9',
    sharedWithGroups: <String>['fam-g2', 'fam-g3'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Yoga mat',
        description: 'Thick, non-slip.',
        url: _link('yoga-mat'),
      ),
      devItemFields(
        'Running shoes',
        description: 'Size 7.',
        url: _link('running-shoes'),
      ),
      devItemFields(
        'Journal',
        description: 'Lined, A5.',
        url: _link('journal'),
      ),
      devItemFields('Book: prize winner', url: _link('prize-winner')),
      devItemFields(
        'Water bottle',
        description: 'Insulated, 1L.',
        url: _link('water-bottle'),
      ),
      devItemFields(
        'Resistance bands',
        url: _link('resistance-bands'),
        claimedBy: 'fam-u8',
        claimedAt: _claimedOn,
      ),
      devItemFields('Silk pillowcase', url: _link('silk-pillowcase')),
      devItemFields('Perfume: neroli'),
    ],
  );

  wishlist(
    'fam-l7',
    name: "Hana's List",
    ownerId: 'fam-u8',
    sharedWithGroups: <String>['fam-g3'],
    items: <Map<String, dynamic>>[
      devItemFields('Theatre tickets', description: 'Anything at the Almeida.'),
      devItemFields('Book: science fiction', url: _link('science-fiction')),
      devItemFields(
        'Tea set',
        description: 'A proper pot and cups.',
        url: _link('tea-set'),
      ),
      devItemFields('Sheet music stand', url: _link('music-stand')),
      devItemFields(
        'Cashmere scarf',
        description: 'Navy.',
        url: _link('cashmere-scarf'),
      ),
      devItemFields('Vinyl: debut', url: _link('debut-vinyl')),
      devItemFields('Desk lamp', url: _link('desk-lamp')),
    ],
  );

  wishlist(
    'fam-l8',
    name: "Fran's Garden",
    ownerId: 'fam-u6',
    sharedWithGroups: <String>['fam-g1'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Rose bushes',
        description: 'Two, pale pink.',
        url: _link('rose-bushes'),
      ),
      devItemFields(
        'Garden gloves',
        description: 'Small.',
        url: _link('gloves'),
      ),
      devItemFields(
        'Bird feeder',
        description: 'Squirrel-proof.',
        url: _link('bird-feeder'),
      ),
      devItemFields('Seed tin', url: _link('seed-tin')),
      devItemFields(
        'Garden bench',
        description: 'Wooden, two-seater.',
        url: _link('garden-bench'),
      ),
      devItemFields(
        'Watering can',
        description: 'Brass.',
        url: _link('watering-can'),
      ),
      devItemFields('Pruning shears'),
    ],
  );

  wishlist(
    'fam-l9',
    name: "Gus's Travel Kit",
    ownerId: 'fam-u7',
    sharedWithGroups: <String>['fam-g2'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Travel wallet',
        description: 'Passport and cards.',
        url: _link('travel-wallet'),
      ),
      devItemFields(
        'Packing cubes',
        description: 'Set of four.',
        url: _link('packing-cubes'),
      ),
      devItemFields(
        'Noise-cancelling headphones',
        description: 'Over-ear, not earbuds.',
        url: _link('anc-headphones'),
        claimedBy: familyViewerUid,
        claimedAt: _claimedOn,
      ),
      devItemFields('Neck pillow', url: _link('neck-pillow')),
      devItemFields('Universal adapter', url: _link('adapter')),
      devItemFields('Luggage scale'),
      devItemFields(
        'Weekender bag',
        description: 'Canvas, tan.',
        url: _link('weekender'),
      ),
    ],
  );

  wishlist(
    'fam-l10',
    name: "Jo's Studio",
    ownerId: 'fam-u10',
    sharedWithGroups: <String>['fam-g3'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Sketchbook',
        description: 'A4, landscape.',
        url: _link('sketchbook'),
      ),
      devItemFields('Architecture book', url: _link('architecture-book')),
      devItemFields(
        'Studio lamp',
        description: 'Daylight, adjustable.',
        url: _link('studio-lamp-2'),
      ),
      devItemFields('Vinyl: debut', url: _link('debut-vinyl-2')),
      devItemFields(
        'Sneakers',
        description: 'Size 10, white.',
        url: _link('sneakers'),
      ),
      devItemFields('Desk chair', description: 'Something mid-century.'),
      devItemFields('Headphones', url: _link('headphones')),
    ],
  );

  wishlist(
    familyViewerWishlistId,
    name: "Ada's Birthday",
    ownerId: familyViewerUid,
    sharedWithGroups: <String>['fam-g1', 'fam-g3'],
    items: <Map<String, dynamic>>[
      devItemFields(
        'Vintage watch',
        description: 'The 1960s one from the auction.',
        url: _link('vintage-watch'),
      ),
      devItemFields(
        'Art book: monographs',
        url: _link('monographs-book'),
        claimedBy: 'fam-u2',
        claimedAt: _claimedOn,
      ),
      devItemFields(
        'Vinyl: reissue',
        description: 'The reissue.',
        url: _link('reissue-vinyl-2'),
      ),
      devItemFields(
        'Cashmere overcoat',
        description: 'Charcoal, medium.',
        url: _link('overcoat'),
      ),
      devItemFields(
        'Espresso machine',
        description: 'The one with the pressure gauge.',
        url: _link('espresso-machine'),
      ),
      devItemFields(
        'Studio headphones',
        url: _link('studio-headphones'),
        claimedBy: 'fam-u3',
        claimedAt: _claimedOn,
      ),
      devItemFields(
        'Cufflinks',
        description: 'Silver, simple.',
        url: _link('cufflinks'),
      ),
      devItemFields(
        'Chess set',
        description: 'Wooden, travel size.',
        url: _link('chess-set'),
      ),
      devItemFields(
        'Running shoes',
        description: 'Size 10.',
        url: _link('running-shoes-2'),
      ),
    ],
  );

  return documents;
}

/// The demo dataset as a committed scenario.
final DevFixture familyFixture = DevFixture(
  id: 'family',
  viewerUid: familyViewerUid,
  documents: _documents(),
);
