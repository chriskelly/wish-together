import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/scenario_items.dart';

/// The viewer of the `large-wishlist` scenario.
const String largeWishlistViewerUid = 'lg-u1';

/// The one wishlist the scenario fills with fifty items.
const String largeWishlistId = 'lg-l1';

/// One long list and nothing else: the scrolling, paging and performance probe.
///
/// The items are generated rather than written out, so their ids are predictable
/// (`lg-i01` to `lg-i50`) and a test can address any row by position. Every
/// third item carries a description and every fifth a link, which keeps the rows
/// from being visually identical while still making the list trivial to extend.
final DevFixture largeWishlistFixture = DevFixture(
  id: 'large-wishlist',
  viewerUid: largeWishlistViewerUid,
  documents: <String, Map<String, dynamic>>{
    'users/$largeWishlistViewerUid': <String, dynamic>{
      'displayName': 'Ada Long',
    },
    'wishlists/$largeWishlistId': <String, dynamic>{
      'name': 'Fifty gift ideas',
      'ownerId': largeWishlistViewerUid,
      'sharedWithGroups': <String>[],
    },
    ...devItems(
      wishlistId: largeWishlistId,
      count: 50,
      id: (index) => 'lg-i${(index + 1).toString().padLeft(2, '0')}',
      fields: (index) {
        final number = index + 1;
        return devItemFields(
          'Gift idea $number',
          description: number % 3 == 0
              ? 'A note for gift idea $number, long enough to take a line.'
              : null,
          url: number % 5 == 0 ? 'https://example.com/gift/idea-$number' : null,
        );
      },
    ),
  },
);
