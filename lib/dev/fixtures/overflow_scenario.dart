import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/scenario_items.dart';

/// The viewer of the `overflow` scenario.
const String overflowViewerUid = 'ovf-u1';

/// Another group member, whose own wishlist is shared with the viewer.
const String overflowOwnerUid = 'ovf-u2';

/// The member whose claim appears on the shared wishlist.
const String overflowClaimerUid = 'ovf-u3';

/// The group that makes the second wishlist readable by the viewer.
const String overflowGroupId = 'ovf-g1';

/// The viewer's own wishlist.
const String overflowWishlistId = 'ovf-l1';

/// Another member's wishlist, shared with the group.
const String overflowSharedWishlistId = 'ovf-l2';

/// The text probes the `overflow` scenario exists to show.
///
/// Each is deliberately past the length a screen has room for. Some are spaced
/// and some are not: a wrapping layout handles a sentence, while an unbroken
/// token is what exposes a row that cannot ellipsise or wrap at all.
const String overflowDisplayName =
    'Alexandria-Cassandra Montgomery-Fitzwilliam of the North Riding';
const String overflowUnbrokenDisplayName =
    'BartholomewMaximilianFeatherstonehaughWorthingtonIII';
const String overflowGroupName =
    'The Extremely Long Named Family Group Assembled For Overflow Testing';
const String overflowWishlistName =
    'A wishlist with a name long enough to test what the app does when the text does not fit';
const String overflowSharedWishlistName =
    'Another deliberately long wishlist name, because one probe is never enough';
const String overflowUnbrokenItemName =
    'SupercalifragilisticexpialidociousSupercalifragilisticexpialidociousSupercalifragilisticexpialidocious';
const String overflowSpacedItemName =
    'A gift with a name long enough to wrap across several lines and still leave the actions where they belong';
const String overflowUrl =
    'https://example.com/gift/a-very-long-product-page-with-a-query-string'
    '?colour=charcoal&size=medium&gift-wrap=true&note=please-do-not-bend'
    '&referrer=dev-session';
const String overflowDescription =
    'A description long enough to fill several lines on a phone and to push '
    'whatever follows it further down the page than a screenshot can hold. It '
    'is almost entirely ordinary prose, so it should wrap at the spaces, and '
    'the only thing it asks a layout to do is grow.';

/// Every place a long string can land: the profile and home greeting, a group
/// name and member list, a wishlist title, an item name, link and description.
///
/// One item is claimed by another member, so the claimed state is rendered with
/// long text around it too.
final DevFixture overflowFixture = DevFixture(
  id: 'overflow',
  viewerUid: overflowViewerUid,
  documents: <String, Map<String, dynamic>>{
    'users/$overflowViewerUid': <String, dynamic>{
      'displayName': overflowDisplayName,
    },
    'users/$overflowOwnerUid': <String, dynamic>{
      'displayName': overflowUnbrokenDisplayName,
    },
    'users/$overflowClaimerUid': <String, dynamic>{
      'displayName': 'Cleo Fields',
    },
    'groups/$overflowGroupId': <String, dynamic>{
      'name': overflowGroupName,
      'ownerId': overflowViewerUid,
      'members': <String>[
        overflowViewerUid,
        overflowOwnerUid,
        overflowClaimerUid,
      ],
    },
    'wishlists/$overflowWishlistId': <String, dynamic>{
      'name': overflowWishlistName,
      'ownerId': overflowViewerUid,
      'sharedWithGroups': <String>[],
    },
    'wishlists/$overflowSharedWishlistId': <String, dynamic>{
      'name': overflowSharedWishlistName,
      'ownerId': overflowOwnerUid,
      'sharedWithGroups': <String>[overflowGroupId],
    },
    'wishlists/$overflowWishlistId/items/ovf-i1': devItemFields(
      overflowUnbrokenItemName,
    ),
    'wishlists/$overflowWishlistId/items/ovf-i2': devItemFields(
      overflowSpacedItemName,
      url: overflowUrl,
    ),
    'wishlists/$overflowWishlistId/items/ovf-i3': devItemFields(
      'Pruning shears',
      description: overflowDescription,
    ),
    'wishlists/$overflowWishlistId/items/ovf-i4': devItemFields(
      'Watering can',
      url: overflowUrl,
    ),
    'wishlists/$overflowSharedWishlistId/items/ovf-i5': devItemFields(
      overflowSpacedItemName,
      description: overflowDescription,
      claims: <String, Timestamp>{overflowClaimerUid: Timestamp.fromDate(DateTime.utc(2026, 9, 20, 18))},
    ),
  },
);
