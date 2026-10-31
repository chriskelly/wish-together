import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';

/// The viewer the `default` scenario signs in.
const String defaultViewerUid = 'dev-u1';

/// The scenario a dev session shows when nothing else is asked for.
///
/// The data is deliberately small but not flat: two wishlists the viewer owns
/// (what the home page lists), one wishlist somebody else owns and shares with
/// the group (the only way to see a claimable item), one group, and one claimed
/// item so the claimed rendering has something to show.
///
/// Open `/wishlist/dev-l3` (or `/group/dev-g1`) to reach the shared pages:
/// nothing links to them from home, because the viewer does not own that
/// wishlist.
final DevFixture defaultFixture = DevFixture(
  id: 'default',
  viewerUid: defaultViewerUid,
  documents: <String, Map<String, dynamic>>{
    'users/dev-u1': <String, dynamic>{'displayName': 'Ana Dev'},
    'users/dev-u2': <String, dynamic>{'displayName': 'Ben Dev'},
    'users/dev-u3': <String, dynamic>{'displayName': 'Cleo Dev'},
    'groups/dev-g1': <String, dynamic>{
      'name': 'Dev Family',
      'ownerId': 'dev-u1',
      'members': <String>['dev-u1', 'dev-u2', 'dev-u3'],
    },
    'wishlists/dev-l1': <String, dynamic>{
      'name': 'Birthday list',
      'ownerId': 'dev-u1',
      'sharedWithGroups': <String>['dev-g1'],
    },
    'wishlists/dev-l2': <String, dynamic>{
      'name': 'Christmas list',
      'ownerId': 'dev-u1',
      'sharedWithGroups': <String>[],
    },
    'wishlists/dev-l3': <String, dynamic>{
      'name': "Ben's list",
      'ownerId': 'dev-u2',
      'sharedWithGroups': <String>['dev-g1'],
    },
    'wishlists/dev-l1/items/dev-i1': <String, dynamic>{
      'name': 'Board game',
      'description': 'A two-player strategy game.',
    },
    'wishlists/dev-l1/items/dev-i2': <String, dynamic>{
      'name': 'Wool scarf',
      'url': 'https://example.com/wool-scarf',
    },
    'wishlists/dev-l1/items/dev-i3': <String, dynamic>{
      'name': 'Coffee grinder',
    },
    'wishlists/dev-l2/items/dev-i4': <String, dynamic>{'name': 'Cookbook'},
    'wishlists/dev-l2/items/dev-i5': <String, dynamic>{'name': 'Hiking boots'},
    'wishlists/dev-l3/items/dev-i6': <String, dynamic>{
      'name': 'Garden trowel',
      'claimedBy': 'dev-u3',
      // Stored the way the app stores it: the repository casts this field to a
      // Timestamp, so an ISO-8601 string would throw on the way in.
      'claimedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 1)),
    },
    'wishlists/dev-l3/items/dev-i7': <String, dynamic>{
      'name': 'Pruning shears',
    },
  },
);
