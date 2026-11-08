import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/domain/claim_limit_reached_exception.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

void main() {
  group('ItemRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ItemRepository itemRepository;

    const String testWishlistId = 'test_wishlist';
    final String itemsCollectionPath =
        '${Wishlist.collectionName}/$testWishlistId/${Item.collectionName}';
    final DateTime claimedAt = DateTime.utc(2026, 11, 1, 12);

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      itemRepository = ItemRepository(testWishlistId, firestore: fakeFirestore);
    });

    Future<void> seed(String itemId, Map<String, dynamic> data) =>
        fakeFirestore.collection(itemsCollectionPath).doc(itemId).set(data);

    Future<Map<String, dynamic>> stored(String itemId) async =>
        (await fakeFirestore
                .collection(itemsCollectionPath)
                .doc(itemId)
                .get())
            .data()!;

    group('claims conversion', () {
      test('toFirestore stores claim times as Timestamps', () {
        final item = Item(
          id: 'item',
          name: 'Gift',
          claims: <String, DateTime>{'u1': claimedAt},
          claimLimit: 2,
        );

        final map = itemRepository.toFirestore(item);

        expect(map['claims'], isA<Map<String, dynamic>>());
        expect((map['claims'] as Map<String, dynamic>)['u1'], isA<Timestamp>());
        expect(
          (map['claims'] as Map<String, dynamic>)['u1'],
          Timestamp.fromDate(claimedAt),
        );
        expect(map['claimLimit'], 2);
      });

      test('fromFirestore reads claim times back as DateTimes', () async {
        await seed('item', <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{
            'u1': Timestamp.fromDate(claimedAt),
            'u2': Timestamp.fromDate(claimedAt.add(const Duration(hours: 1))),
          },
          'claimLimit': 3,
        });

        final doc = await fakeFirestore
            .collection(itemsCollectionPath)
            .doc('item')
            .get();
        final item = itemRepository.fromFirestore(doc);

        expect(item.claims['u1'], claimedAt);
        expect(item.claimCount, 2);
        expect(item.claimLimit, 3);
        expect(item.toMap()['claims'], isA<Map<String, dynamic>>());
      });

      test('fromFirestore drops a stored claim value that is not a '
          'Timestamp instead of failing the read', () async {
        await seed('item', <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{
            'u1': 'not-a-date',
            'u2': 7,
            'u3': Timestamp.fromDate(claimedAt),
          },
          'claimLimit': 1,
        });

        final doc = await fakeFirestore
            .collection(itemsCollectionPath)
            .doc('item')
            .get();
        final item = itemRepository.fromFirestore(doc);

        expect(item.claims.keys, orderedEquals(<String>['u3']));
        expect(item.claims['u3'], claimedAt);
      });
    });

    group('claim', () {
      test('adds only the claim key and leaves the content untouched', () async {
        const itemId = 'stale_item';
        const storedName = 'Renamed by the owner';
        const storedDescription = 'Stored description';
        const storedUrl = 'https://example.com/stored';
        const readerUid = 'reader-1';
        await seed(itemId, <String, dynamic>{
          'name': storedName,
          'description': storedDescription,
          'url': storedUrl,
          'claims': <String, dynamic>{},
          'claimLimit': 1,
        });

        await itemRepository.claim(itemId, claimedBy: readerUid);

        final data = await stored(itemId);
        final claims = data['claims'] as Map<String, dynamic>;
        expect(claims[readerUid], isA<Timestamp>());
        expect(data['name'], storedName);
        expect(data['description'], storedDescription);
        expect(data['url'], storedUrl);
      });

      test('does not add an optional field the stored item lacks', () async {
        const itemId = 'sparse_item';
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{},
          'claimLimit': 1,
        });

        await itemRepository.claim(itemId, claimedBy: 'reader-1');

        final data = await stored(itemId);
        expect(data.containsKey('description'), isFalse);
        expect(data.containsKey('url'), isFalse);
      });

      test('claiming twice for the same uid keeps one key and the original time',
          () async {
        const itemId = 'double_tap';
        const readerUid = 'reader-1';
        final firstClaimAt = DateTime.utc(2026, 1, 1);
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{
            readerUid: Timestamp.fromDate(firstClaimAt),
          },
          'claimLimit': 1,
        });

        await itemRepository.claim(itemId, claimedBy: readerUid);

        final claims = (await stored(itemId))['claims'] as Map<String, dynamic>;
        expect(claims.keys, orderedEquals(<String>[readerUid]));
        expect(claims[readerUid], Timestamp.fromDate(firstClaimAt));
      });

      test('rejects a claim on a full finite item and writes nothing', () async {
        const itemId = 'full_item';
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{
            'someone-else': Timestamp.fromDate(claimedAt),
          },
          'claimLimit': 1,
        });

        await expectLater(
          itemRepository.claim(itemId, claimedBy: 'reader-1'),
          throwsA(isA<ClaimLimitReachedException>()),
        );

        final claims = (await stored(itemId))['claims'] as Map<String, dynamic>;
        expect(claims.containsKey('reader-1'), isFalse);
        expect(claims.keys, orderedEquals(<String>['someone-else']));
      });

      test('accepts a claim one below the limit', () async {
        const itemId = 'room_left';
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{
            'someone-else': Timestamp.fromDate(claimedAt),
          },
          'claimLimit': 2,
        });

        await itemRepository.claim(itemId, claimedBy: 'reader-1');

        final claims = (await stored(itemId))['claims'] as Map<String, dynamic>;
        expect(claims.keys, containsAll(<String>['someone-else', 'reader-1']));
      });

      test('accepts several distinct uids on an unlimited item', () async {
        const itemId = 'unlimited_item';
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{},
          'claimLimit': 0,
        });

        await itemRepository.claim(itemId, claimedBy: 'reader-1');
        await itemRepository.claim(itemId, claimedBy: 'reader-2');
        await itemRepository.claim(itemId, claimedBy: 'reader-3');

        final claims = (await stored(itemId))['claims'] as Map<String, dynamic>;
        expect(
          claims.keys,
          unorderedEquals(<String>['reader-1', 'reader-2', 'reader-3']),
        );
      });

      test('reports a missing item as not-found', () async {
        await expectLater(
          itemRepository.claim('missing_item', claimedBy: 'reader-1'),
          throwsA(
            isA<FirebaseException>().having(
              (error) => error.code,
              'code',
              'not-found',
            ),
          ),
        );
      });
    });

    group('unclaim', () {
      test('removes only the caller key and leaves another claim intact',
          () async {
        const itemId = 'two_claims';
        final otherClaimAt = DateTime.utc(2026, 10, 1);
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'claims': <String, dynamic>{
            'reader-1': Timestamp.fromDate(claimedAt),
            'reader-2': Timestamp.fromDate(otherClaimAt),
          },
          'claimLimit': 2,
        });

        await itemRepository.unclaim(itemId, claimedBy: 'reader-1');

        final data = await stored(itemId);
        final claims = data['claims'] as Map<String, dynamic>;
        expect(claims.keys, orderedEquals(<String>['reader-2']));
        expect(claims['reader-2'], Timestamp.fromDate(otherClaimAt));
        expect(data['name'], 'Gift');
      });
    });

    group('updateContent', () {
      test('writes the four content fields and preserves the claims', () async {
        const itemId = 'content_edit';
        await seed(itemId, <String, dynamic>{
          'name': 'Old name',
          'description': 'Old description',
          'url': 'https://old.example.com',
          'claims': <String, dynamic>{
            'reader-1': Timestamp.fromDate(claimedAt),
          },
          'claimLimit': 1,
        });

        await itemRepository.updateContent(
          itemId,
          name: 'New name',
          description: 'New description',
          url: 'https://new.example.com',
          claimLimit: 3,
        );

        final data = await stored(itemId);
        expect(data['name'], 'New name');
        expect(data['description'], 'New description');
        expect(data['url'], 'https://new.example.com');
        expect(data['claimLimit'], 3);
        final claims = data['claims'] as Map<String, dynamic>;
        expect(claims.keys, orderedEquals(<String>['reader-1']));
        expect(claims['reader-1'], Timestamp.fromDate(claimedAt));
      });

      test('writes null when the description and url are cleared', () async {
        const itemId = 'clear_content';
        await seed(itemId, <String, dynamic>{
          'name': 'Gift',
          'description': 'Old description',
          'url': 'https://old.example.com',
          'claims': <String, dynamic>{},
          'claimLimit': 1,
        });

        await itemRepository.updateContent(
          itemId,
          name: 'Gift',
          description: null,
          url: null,
          claimLimit: 1,
        );

        final data = await stored(itemId);
        expect(data['description'], isNull);
        expect(data['url'], isNull);
      });
    });
  });
}
