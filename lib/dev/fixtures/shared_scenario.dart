import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/scenario_items.dart';

/// The viewer of the `shared` scenario.
const String sharedViewerUid = 'shr-u1';

/// The member who owns the wishlist shared with the whole group.
const String sharedOwnerUid = 'shr-u2';

/// The member whose claims the viewer can see.
const String sharedClaimerUid = 'shr-u3';

/// A fourth member, which makes the member list more than the two names a claim
/// needs.
const String sharedMemberUid = 'shr-u4';

/// The group both wishlists are shared with.
const String sharedGroupId = 'shr-g1';

/// The viewer's own wishlist, shared with the group.
const String sharedViewerWishlistId = 'shr-l1';

/// Another member's wishlist, shared with the group.
const String sharedOtherWishlistId = 'shr-l2';

/// A wishlist a group can see, with claims made by people other than its owner.
///
/// Home lists groups, not wishlists shared with them, so the way in is
/// `/group/shr-g1`: the group page lists both wishlists below. The viewer does
/// not own the second one, so its claims are visible without the owner's
/// spoiler toggle; the first one is the viewer's, so the toggle has a claim to
/// hide and reveal.
///
/// The second list carries every reader rendering: another member's full
/// single claim (`Unavailable`), the viewer's single claim, an unlimited item
/// with a count, a partly claimed finite item, a full finite item and the
/// viewer's own multi claim. The first list carries the owner labels: a single
/// limit, an unlimited item and two finite multi limits (one with no claims).
final DevFixture sharedFixture = DevFixture(
  id: 'shared',
  viewerUid: sharedViewerUid,
  documents: <String, Map<String, dynamic>>{
    'users/$sharedViewerUid': <String, dynamic>{'displayName': 'Sam Rivera'},
    'users/$sharedOwnerUid': <String, dynamic>{'displayName': 'Priya Nair'},
    'users/$sharedClaimerUid': <String, dynamic>{'displayName': 'Tom Okafor'},
    'users/$sharedMemberUid': <String, dynamic>{'displayName': 'Lena Fields'},
    'groups/$sharedGroupId': <String, dynamic>{
      'name': 'The Riveras',
      'ownerId': sharedOwnerUid,
      'members': <String>[
        sharedViewerUid,
        sharedOwnerUid,
        sharedClaimerUid,
        sharedMemberUid,
      ],
    },
    'wishlists/$sharedViewerWishlistId': <String, dynamic>{
      'name': "Sam's Birthday",
      'ownerId': sharedViewerUid,
      'sharedWithGroups': <String>[sharedGroupId],
    },
    'wishlists/$sharedOtherWishlistId': <String, dynamic>{
      'name': "Priya's Wedding List",
      'ownerId': sharedOwnerUid,
      'sharedWithGroups': <String>[sharedGroupId],
    },
    'wishlists/$sharedViewerWishlistId/items/shr-i1': devItemFields(
      'Espresso machine',
      description: 'The one with the pressure gauge.',
      url: 'https://example.com/gift/espresso-machine',
    ),
    'wishlists/$sharedViewerWishlistId/items/shr-i2': devItemFields(
      'Hiking boots',
      description: 'Size 10, waterproof.',
      claims: <String, Timestamp>{
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 21, 9)),
      },
    ),
    'wishlists/$sharedViewerWishlistId/items/shr-i11': devItemFields(
      'Stand mixer',
      claimLimit: 0,
      claims: <String, Timestamp>{
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 24, 9)),
        sharedMemberUid: Timestamp.fromDate(DateTime.utc(2026, 9, 24, 10)),
      },
    ),
    'wishlists/$sharedViewerWishlistId/items/shr-i12': devItemFields(
      'Garden chair',
      claimLimit: 3,
      claims: <String, Timestamp>{
        sharedMemberUid: Timestamp.fromDate(DateTime.utc(2026, 9, 24, 11)),
      },
    ),
    'wishlists/$sharedViewerWishlistId/items/shr-i13': devItemFields(
      'Fire pit',
      claimLimit: 3,
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i3': devItemFields(
      'Serving platter',
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i4': devItemFields(
      "Chef's knife",
      description: 'The long one, not the set.',
      url: 'https://example.com/gift/chefs-knife',
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i5': devItemFields(
      'Cast iron skillet',
      description: 'Twelve inch, pre-seasoned.',
      claims: <String, Timestamp>{
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 22, 17)),
      },
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i6': devItemFields(
      'Tea towel set',
      claims: <String, Timestamp>{
        sharedViewerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 23, 11)),
      },
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i7': devItemFields(
      'Garden hose',
      claimLimit: 0,
      claims: <String, Timestamp>{
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 9)),
        sharedMemberUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 10)),
      },
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i8': devItemFields(
      'Picnic set',
      claimLimit: 3,
      claims: <String, Timestamp>{
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 11)),
      },
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i9': devItemFields(
      'Camping stove',
      claimLimit: 2,
      claims: <String, Timestamp>{
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 12)),
        sharedMemberUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 13)),
      },
    ),
    'wishlists/$sharedOtherWishlistId/items/shr-i10': devItemFields(
      'Board game',
      claimLimit: 4,
      claims: <String, Timestamp>{
        sharedViewerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 14)),
        sharedClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 25, 15)),
      },
    ),
  },
);
