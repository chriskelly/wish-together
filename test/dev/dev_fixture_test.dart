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
int claimsIn(DevFixture fixture) => fixture.documents.values.where((document) {
  final claims = document['claims'];
  return claims is Map && claims.isNotEmpty;
}).length;

/// The id of every document directly inside [collection].
///
/// Nested documents (an item under a wishlist) are not included: their parent
/// collection is addressed by the path, not by the collection name alone.
Set<String> idsIn(DevFixture fixture, String collection) {
  final ids = <String>{};
  for (final path in fixture.documents.keys) {
    final segments = path.split('/');
    if (segments.length == 2 && segments.first == collection) {
      ids.add(segments.last);
    }
  }
  return ids;
}

void main() {
  // Every committed scenario is held to the same shape rules, so a new one
  // cannot quietly divert to onboarding or throw on a malformed item.
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
        // production runs, including each claim's Timestamp.
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
              final document = await firestore.doc(entry.key).get();
              final item = repository.fromFirestore(document);
              expect(item.id, itemId);
              final rawClaims = entry.value['claims'];
              if (rawClaims is Map && rawClaims.isNotEmpty) {
                expect(
                  item.claimCount,
                  rawClaims.length,
                  reason:
                      'every stored claim must be readable; the repository '
                      'converts Timestamp values and drops anything else',
                );
              }
            default:
              fail('unrecognised fixture path: ${entry.key}');
          }
        }
      });

      test('keys every document by a full, non-empty document path', () {
        // The seeding loop hands each key straight to `firestore.doc()`, which
        // asserts on an even number of non-empty segments. A malformed key
        // would therefore fail at boot, not here, so the shape is pinned where
        // a scenario author can read the failure.
        for (final path in fixture.documents.keys) {
          final segments = path.split('/');

          expect(
            segments.length.isEven,
            isTrue,
            reason: '"$path" is not a document path',
          );
          expect(
            segments,
            everyElement(isNotEmpty),
            reason: '"$path" has an empty segment',
          );
        }
      });

      test('uses every document id once, so an id names one document', () {
        // An id is a handle: an agent pastes it into a URL, a log line or a
        // test. Firestore only requires uniqueness inside a collection, but a
        // fixture where one id names two documents makes the handle ambiguous,
        // so every scenario keeps its ids distinct across the whole fixture.
        //
        // The item generators assert against a duplicate path as they build;
        // this sweep holds the hand-written documents to the same rule.
        final pathById = <String, String>{};
        final reused = <String>[];

        for (final path in fixture.documents.keys) {
          final id = path.split('/').last;
          final previous = pathById[id];
          if (previous != null) {
            reused.add('$id at "$previous" and "$path"');
          }
          pathById[id] = path;
        }

        expect(
          reused,
          isEmpty,
          reason: 'these ids name more than one document: ${reused.join('; ')}',
        );
      });

      test('names only seeded users as owners, members and claimers', () {
        final userIds = idsIn(fixture, User.collectionName);
        final broken = <String>[];

        for (final entry in fixture.documents.entries) {
          final segments = entry.key.split('/');
          if (segments case [Group.collectionName, final id]) {
            final group = Group.fromMap(entry.value, id);
            if (!userIds.contains(group.ownerId)) {
              broken.add('group $id is owned by ${group.ownerId}');
            }
            if (!group.members.contains(group.ownerId)) {
              broken.add('group $id does not list its owner as a member');
            }
            for (final member in group.members.where(
              (member) => !userIds.contains(member),
            )) {
              broken.add('group $id lists member $member');
            }
          } else if (segments case [Wishlist.collectionName, final id]) {
            final wishlist = Wishlist.fromMap(entry.value, id);
            if (!userIds.contains(wishlist.ownerId)) {
              broken.add('wishlist $id is owned by ${wishlist.ownerId}');
            }
          } else if (segments case [
            Wishlist.collectionName,
            final wishlistId,
            Item.collectionName,
            final id,
          ]) {
            final claims = entry.value['claims'];
            if (claims is Map) {
              for (final uid in claims.keys) {
                if (uid is! String || !userIds.contains(uid)) {
                  broken.add('item $wishlistId/$id is claimed by $uid');
                }
              }
            }
          }
        }

        expect(
          broken,
          isEmpty,
          reason: 'unseeded user ids: ${broken.join('; ')}',
        );
      });

      test('shares wishlists only with seeded groups', () {
        final groupIds = idsIn(fixture, Group.collectionName);
        final broken = <String>[];

        for (final wishlist in wishlistsIn(fixture)) {
          for (final groupId in wishlist.sharedWithGroups.where(
            (groupId) => !groupIds.contains(groupId),
          )) {
            broken.add('wishlist ${wishlist.id} is shared with $groupId');
          }
        }

        expect(
          broken,
          isEmpty,
          reason: 'unseeded group ids: ${broken.join('; ')}',
        );
      });

      test('shares wishlists only with groups their owner belongs to', () {
        // The ordinary flow shares from a group page, which offers the sharer's
        // own wishlists and is normally reached from a membership, so this
        // library keeps lists shared only with groups their owner is in.
        //
        // It is a convention, not a rule production enforces: `groups` reads are
        // open to any signed-in user and the share button is not gated on
        // membership, so a non-member who knows the group id can share their own
        // list into it. If a scenario ever needs that state, remove this check
        // deliberately rather than reshaping the data to satisfy it.
        final groups = <String, Group>{};
        for (final id in idsIn(fixture, Group.collectionName)) {
          groups[id] = Group.fromMap(
            fixture.documents['${Group.collectionName}/$id']!,
            id,
          );
        }
        final broken = <String>[];

        for (final wishlist in wishlistsIn(fixture)) {
          for (final groupId in wishlist.sharedWithGroups) {
            // An unknown group is the sibling test's finding; here it would only
            // turn a collected failure into a bare null-check error.
            final group = groups[groupId];
            if (group == null) {
              continue;
            }
            if (!group.members.contains(wishlist.ownerId)) {
              broken.add(
                'wishlist ${wishlist.id} (owner ${wishlist.ownerId}) is '
                'shared with $groupId, which does not list the owner as a member',
              );
            }
          }
        }

        expect(broken, isEmpty);
      });

      test('makes every wishlist reachable by the viewer', () {
        // A wishlist the viewer neither owns nor shares with one of their
        // groups is dead weight: no row links to it, so only a hand-written URL
        // could open it, and a scenario full of those shows nothing.
        final groups = <String, Group>{};
        for (final id in idsIn(fixture, Group.collectionName)) {
          groups[id] = Group.fromMap(
            fixture.documents['${Group.collectionName}/$id']!,
            id,
          );
        }
        final unreachable = <String>[];

        for (final wishlist in wishlistsIn(fixture)) {
          final owned = wishlist.ownerId == fixture.viewerUid;
          final sharedWithViewer = wishlist.sharedWithGroups.any(
            (groupId) =>
                groups[groupId]?.members.contains(fixture.viewerUid) ?? false,
          );
          if (!owned && !sharedWithViewer) {
            unreachable.add('${wishlist.id} (owner ${wishlist.ownerId})');
          }
        }

        expect(unreachable, isEmpty);
      });

      test('puts items only under wishlists the scenario seeds', () {
        final wishlistIds = idsIn(fixture, Wishlist.collectionName);
        final orphaned = <String>[];

        for (final path in fixture.documents.keys) {
          if (path.split('/') case [
            Wishlist.collectionName,
            final wishlistId,
            Item.collectionName,
            _,
          ]) {
            if (!wishlistIds.contains(wishlistId)) {
              orphaned.add(path);
            }
          }
        }

        expect(orphaned, isEmpty);
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
