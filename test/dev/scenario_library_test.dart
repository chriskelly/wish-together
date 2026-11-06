import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/empty_scenario.dart';
import 'package:wishtogether/dev/fixtures/family_scenario.dart';
import 'package:wishtogether/dev/fixtures/large_wishlist_scenario.dart';
import 'package:wishtogether/dev/fixtures/overflow_scenario.dart';
import 'package:wishtogether/dev/fixtures/registry.dart';
import 'package:wishtogether/dev/fixtures/scenario_items.dart';
import 'package:wishtogether/dev/fixtures/shared_scenario.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

// The cross-scenario contract suite: the documented ids, the properties a
// scenario exists to provide, the generated-item helper, and the one-off
// workflow. It has no single `lib/` counterpart because it holds the registry
// and every fixture module to the same published contract.

/// The field maps of every item document, with the wishlist that holds it.
Iterable<({String wishlistId, Map<String, dynamic> fields})> itemsIn(
  DevFixture fixture,
) sync* {
  for (final entry in fixture.documents.entries) {
    if (entry.key.split('/') case [
      Wishlist.collectionName,
      final wishlistId,
      Item.collectionName,
      _,
    ]) {
      yield (wishlistId: wishlistId, fields: entry.value);
    }
  }
}

/// How many documents [fixture] holds directly in [collection].
int countIn(DevFixture fixture, String collection) {
  var count = 0;
  for (final path in fixture.documents.keys) {
    final segments = path.split('/');
    if (segments.length == 2 && segments.first == collection) {
      count += 1;
    }
  }
  return count;
}

/// Every document id in [fixture], whether top-level or under a wishlist.
Set<String> documentIdsIn(DevFixture fixture) => <String>{
  for (final path in fixture.documents.keys) path.split('/').last,
};

void main() {
  group('devItems', () {
    test('builds the requested number of items under the wishlist', () {
      const wishlistId = 'lg-l1';
      const requested = 4;

      final documents = devItems(
        wishlistId: wishlistId,
        count: requested,
        id: (index) => 'generated-$index',
        fields: (index) => devItemFields('Gift $index'),
      );

      expect(documents, hasLength(requested));
      for (var index = 0; index < requested; index++) {
        final path = 'wishlists/$wishlistId/items/generated-$index';
        expect(documents[path]?['name'], 'Gift $index');
      }
    });

    test('refuses to generate two items with the same id', () {
      // A map keeps only the last of two identical keys, so the generator is
      // the place where a repeated id would otherwise vanish silently.
      expect(
        () => devItems(
          wishlistId: 'lg-l1',
          count: 2,
          id: (_) => 'same-id',
          fields: (index) => devItemFields('Gift $index'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('devItemFields', () {
    test('omits the optional fields an item does not set', () {
      const name = 'Board game';

      final fields = devItemFields(name);

      expect(fields, <String, dynamic>{'name': name});
    });

    test('carries a claim as a uid and a Timestamp', () {
      const claimedBy = 'fam-u4';
      final claimedAt = Timestamp.fromDate(DateTime.utc(2026, 9, 20));

      final fields = devItemFields(
        'Dance heels',
        claimedBy: claimedBy,
        claimedAt: claimedAt,
      );

      expect(fields['claimedBy'], claimedBy);
      expect(fields['claimedAt'], same(claimedAt));
    });

    test('rejects a claim that has no timestamp', () {
      // The repository casts the stored timestamp, and the rules treat the two
      // fields as a pair, so half a claim is a fixture that cannot be read back.
      expect(
        () => devItemFields('Dance heels', claimedBy: 'fam-u4'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the family scenario', () {
    test('holds ten people, three groups and eleven wishlists', () {
      expect(countIn(familyFixture, User.collectionName), 10);
      expect(countIn(familyFixture, Group.collectionName), 3);
      expect(countIn(familyFixture, Wishlist.collectionName), 11);
      expect(itemsIn(familyFixture).length, 86);
    });

    test('puts the viewer in every group', () {
      final groups = [
        for (final id in familyFixture.documents.keys)
          if (id.split('/') case [Group.collectionName, final groupId])
            Group.fromMap(familyFixture.documents[id]!, groupId),
      ];

      expect(groups, hasLength(3));
      expect(
        groups,
        everyElement(
          isA<Group>().having(
            (group) => group.members,
            'members',
            contains(familyFixture.viewerUid),
          ),
        ),
      );
    });

    test('claims items on a list the viewer owns and on one they do not', () {
      final ownersOfClaimedLists = <String>{
        for (final item in itemsIn(familyFixture))
          if (item.fields['claimedBy'] != null)
            Wishlist.fromMap(
              familyFixture.documents['wishlists/${item.wishlistId}']!,
              item.wishlistId,
            ).ownerId,
      };

      expect(ownersOfClaimedLists, contains(familyFixture.viewerUid));
      expect(
        ownersOfClaimedLists.any((owner) => owner != familyFixture.viewerUid),
        isTrue,
        reason:
            'the reader-side claim rendering needs a claim the viewer '
            'can see without using the spoiler toggle',
      );
    });
  });

  group('the large-wishlist scenario', () {
    test('fills its one wishlist with fifty items', () {
      final names = <String>{};

      for (final item in itemsIn(largeWishlistFixture)) {
        expect(item.wishlistId, largeWishlistId);
        names.add(item.fields['name'] as String);
      }

      expect(countIn(largeWishlistFixture, Wishlist.collectionName), 1);
      expect(itemsIn(largeWishlistFixture), hasLength(50));
      expect(
        names,
        hasLength(50),
        reason: 'a duplicated name would mean the generator repeated itself',
      );
    });

    test('is owned by the viewer', () {
      final wishlist = Wishlist.fromMap(
        largeWishlistFixture.documents['wishlists/$largeWishlistId']!,
        largeWishlistId,
      );

      expect(wishlist.ownerId, largeWishlistFixture.viewerUid);
    });
  });

  group('the empty scenario', () {
    test('seeds only the viewer profile', () {
      expect(emptyFixture.documents.keys, <String>[
        'users/${emptyFixture.viewerUid}',
      ]);
    });
  });

  group('the overflow scenario', () {
    test('carries display names too long for the app bar', () {
      final displayNames = <String>[
        for (final id in overflowFixture.documents.keys)
          if (id.split('/') case [User.collectionName, _])
            overflowFixture.documents[id]!['displayName'] as String,
      ];

      expect(
        displayNames.any((name) => name.length >= 60 && name.contains(' ')),
        isTrue,
        reason: 'a long spaced name is what tests wrapping in the app bar',
      );
      expect(
        displayNames.any((name) => name.length >= 40 && !name.contains(' ')),
        isTrue,
        reason: 'an unbroken name is what exposes a row that cannot wrap',
      );
    });

    test('carries group and wishlist names past the screen width', () {
      final groupName =
          overflowFixture.documents['groups/$overflowGroupId']!['name']
              as String;
      final wishlistNames = <String>[
        for (final id in overflowFixture.documents.keys)
          if (id.split('/') case [Wishlist.collectionName, _])
            overflowFixture.documents[id]!['name'] as String,
      ];

      expect(groupName.length, greaterThanOrEqualTo(60));
      expect(wishlistNames, hasLength(2));
      expect(wishlistNames.every((name) => name.length >= 70), isTrue);
    });

    test('carries item text, links and descriptions past their containers', () {
      final unbrokenName =
          overflowFixture
                  .documents['wishlists/$overflowWishlistId/items/ovf-i1']!['name']
              as String;
      final urls = [
        for (final item in itemsIn(overflowFixture))
          if (item.fields['url'] != null) item.fields['url'] as String,
      ];
      final descriptions = [
        for (final item in itemsIn(overflowFixture))
          if (item.fields['description'] != null)
            item.fields['description'] as String,
      ];

      expect(unbrokenName, isNot(contains(' ')));
      expect(unbrokenName.length, greaterThanOrEqualTo(80));
      expect(urls, isNotEmpty);
      expect(urls.every((url) => url.length >= 140), isTrue);
      expect(descriptions, isNotEmpty);
      expect(descriptions.every((text) => text.length >= 200), isTrue);
    });
  });

  group('the shared scenario', () {
    test('shares another member\'s wishlist with a group the viewer is in', () {
      final group = Group.fromMap(
        sharedFixture.documents['groups/$sharedGroupId']!,
        sharedGroupId,
      );
      final wishlist = Wishlist.fromMap(
        sharedFixture.documents['wishlists/$sharedOtherWishlistId']!,
        sharedOtherWishlistId,
      );

      expect(group.members, contains(sharedFixture.viewerUid));
      expect(group.members, contains(wishlist.ownerId));
      expect(wishlist.ownerId, isNot(sharedFixture.viewerUid));
      expect(wishlist.sharedWithGroups, contains(sharedGroupId));
    });

    test(
      'carries claims by another member, by the viewer and no claim at all',
      () {
        final items = itemsIn(sharedFixture).toList();
        final claimedBy = items
            .map((item) => item.fields['claimedBy'])
            .whereType<String>();

        expect(
          claimedBy.where((uid) => uid == sharedClaimerUid).length,
          greaterThanOrEqualTo(2),
        );
        expect(claimedBy, contains(sharedFixture.viewerUid));
        expect(items.any((item) => item.fields['claimedBy'] == null), isTrue);
      },
    );
  });

  group('the documented document ids', () {
    // The ids are a published contract: an agent deep-links to them and
    // lib/dev/docs/scenarios.md lists them. A count assertion alone would stay
    // green if a scheme changed, so each scenario's id set is pinned here.

    test(
      'default exposes its three users, group, three lists and seven items',
      () {
        expect(documentIdsIn(defaultFixture), <String>{
          'dev-u1',
          'dev-u2',
          'dev-u3',
          'dev-g1',
          'dev-l1',
          'dev-l2',
          'dev-l3',
          for (var number = 1; number <= 7; number++) 'dev-i$number',
        });
      },
    );

    test('family exposes ten people, three groups, eleven lists and items 01 to 86', () {
      expect(documentIdsIn(familyFixture), <String>{
        for (var number = 1; number <= 10; number++) 'fam-u$number',
        for (var number = 1; number <= 3; number++) 'fam-g$number',
        for (var number = 1; number <= 11; number++) 'fam-l$number',
        for (var number = 1; number <= 86; number++)
          'fam-i${number.toString().padLeft(2, '0')}',
      });
    });

    test('large-wishlist exposes one user, one list and items 01 to 50', () {
      expect(documentIdsIn(largeWishlistFixture), <String>{
        'lg-u1',
        'lg-l1',
        for (var number = 1; number <= 50; number++)
          'lg-i${number.toString().padLeft(2, '0')}',
      });
    });

    test('empty exposes only emp-u1', () {
      expect(documentIdsIn(emptyFixture), <String>{'emp-u1'});
    });

    test(
      'overflow exposes three people, a group, two lists and five items',
      () {
        expect(documentIdsIn(overflowFixture), <String>{
          'ovf-u1',
          'ovf-u2',
          'ovf-u3',
          'ovf-g1',
          'ovf-l1',
          'ovf-l2',
          for (var number = 1; number <= 5; number++) 'ovf-i$number',
        });
      },
    );

    test('shared exposes four people, a group, two lists and six items', () {
      expect(documentIdsIn(sharedFixture), <String>{
        'shr-u1',
        'shr-u2',
        'shr-u3',
        'shr-u4',
        'shr-g1',
        'shr-l1',
        'shr-l2',
        for (var number = 1; number <= 6; number++) 'shr-i$number',
      });
    });
  });

  group('the registry', () {
    test('registers exactly the documented scenarios', () {
      // Two fixtures that share an id would collapse into one map entry and
      // silently hide a scenario, so the set is pinned rather than "at least".
      expect(devScenarios.keys.toList()..sort(), <String>[
        'default',
        'empty',
        'family',
        'large-wishlist',
        'overflow',
        'shared',
      ]);
    });
  });

  group('the one-off scenario directory', () {
    test('is referenced by no source file', () {
      // A tracked file that imports a gitignored one breaks a fresh clone,
      // because the file is not there. Build the needle at runtime so this test
      // does not match itself.
      final needle = <String>['scenarios', 'local'].join('/');
      final references = <String>[];

      for (final root in <String>['lib', 'test']) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          // This file names the directory on purpose, in the test below.
          if (entity.uri.pathSegments.last == 'scenario_library_test.dart') {
            continue;
          }
          // The one-off tree is the directory's own content, not a reference to
          // it; a developer's private header comment must not fail the suite.
          if (entity.path.startsWith('lib/dev/scenarios/local/')) {
            continue;
          }
          if (entity.readAsStringSync().contains(needle)) {
            references.add(entity.path);
          }
        }
      }

      expect(references, isEmpty);
    });

    test('stays out of git, so an absent directory cannot dirty the tree', () {
      final ignored = File('.gitignore')
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'));

      expect(ignored, contains('lib/dev/scenarios/local/'));
    });
  });
}
