import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/registry.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

/// Every wishlist a fixture holds, parsed from its own document.
List<Wishlist> wishlistsIn(DevFixture fixture) => <Wishlist>[
  for (final entry in fixture.documents.entries)
    if (entry.key.split('/') case [Wishlist.collectionName, final id])
      Wishlist.fromMap(entry.value, id),
];

/// The number of documents a fixture marks as claimed.
int claimsIn(DevFixture fixture) => fixture.documents.values
    .where((document) => document['claimedBy'] != null)
    .length;

void main() {
  // Every committed scenario is held to the same shape rules, so the second
  // one cannot quietly divert to onboarding or throw on a malformed item.
  for (final fixture in devScenarios.values) {
    group('the ${fixture.id} scenario', () {
      test('signs in a viewer whose profile already has a display name', () {
        // The router sends a signed-in user with no display name to onboarding,
        // so a fixture without one never reaches the screens it was written for.
        final userDocument = fixture.documents['users/${fixture.viewerUid}'];

        expect(userDocument, isNotNull);
        final displayName = userDocument!['displayName'] as String?;
        expect(displayName, isNotNull);
        expect(displayName, isNotEmpty);
      });

      test('parses every document through its model', () async {
        // Fixtures are Firestore-shaped maps, so the parse has to be the real
        // one: seeding the fake and reading back exercises the same conversion
        // production runs, including the claimedAt Timestamp.
        final firestore = FakeFirebaseFirestore();
        await seedDevFirestore(firestore, fixture);

        for (final entry in fixture.documents.entries) {
          final segments = entry.key.split('/');
          final data = entry.value;
          switch (segments) {
            case [User.collectionName, final id]:
              expect(User.fromMap(data, id).id, id);
            case [Group.collectionName, final id]:
              expect(Group.fromMap(data, id).id, id);
            case [Wishlist.collectionName, final id]:
              expect(Wishlist.fromMap(data, id).id, id);
            case [
              Wishlist.collectionName,
              final wishlistId,
              Item.collectionName,
              final itemId,
            ]:
              final repository = ItemRepository(
                wishlistId,
                firestore: firestore,
              );
              final document = await firestore
                  .collection(
                    '${Wishlist.collectionName}/$wishlistId/${Item.collectionName}',
                  )
                  .doc(itemId)
                  .get();
              final item = repository.fromFirestore(document);
              expect(item.id, itemId);
              if (item.claimedBy != null) {
                expect(
                  item.claimedAt,
                  isNotNull,
                  reason:
                      'a claimed item must carry a claimedAt Timestamp; the '
                      'repository casts the field, so a string would throw',
                );
              }
            default:
              fail('unrecognised fixture path: ${entry.key}');
          }
        }
      });
    });
  }

  group('the default scenario', () {
    test('carries a wishlist the viewer owns and one they do not', () {
      // Owned wishlists are what home lists; a wishlist owned by someone else
      // and shared with a group is the only way to reach a claimable item.
      final wishlists = wishlistsIn(defaultFixture);
      final owned = wishlists.where(
        (wishlist) => wishlist.ownerId == defaultFixture.viewerUid,
      );
      final unowned = wishlists.where(
        (wishlist) => wishlist.ownerId != defaultFixture.viewerUid,
      );

      expect(owned, isNotEmpty);
      expect(unowned, isNotEmpty);
      expect(
        unowned.map((wishlist) => wishlist.sharedWithGroups),
        everyElement(isNotEmpty),
        reason: 'an unowned wishlist the viewer cannot read is useless',
      );
    });

    test('marks exactly one item as claimed', () {
      // The claimed rendering needs something to show, and more than one claim
      // would make "the claimed item" ambiguous in a screenshot.
      expect(claimsIn(defaultFixture), 1);
    });
  });

  group('the registry', () {
    test('keeps every fixture id and registry key in step', () {
      expect(devScenarios, isNotEmpty);
      for (final entry in devScenarios.entries) {
        expect(entry.value.id, entry.key);
      }
    });

    test('resolves a registered id to its fixture', () {
      expect(fixtureForScenario(defaultFixture.id), same(defaultFixture));
    });

    test('fails loudly on an unknown id, naming what is available', () {
      // An agent must never silently see the wrong data.
      const requested = 'no-such-scenario';

      expect(
        () => fixtureForScenario(requested),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains(requested), contains(defaultFixture.id)),
          ),
        ),
      );
    });
  });
}
