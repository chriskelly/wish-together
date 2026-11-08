import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

void main() {
  group('Item claims', () {
    final claimedAt = DateTime.utc(2026, 11, 1, 12);
    final otherClaim = DateTime.utc(2026, 11, 2, 9);

    test('claimCount is the number of claims', () {
      final item = Item(
        name: 'Gift',
        claims: <String, DateTime>{'u1': claimedAt, 'u2': otherClaim},
      );

      expect(item.claimCount, 2);
      expect(Item(name: 'Gift').claimCount, 0);
    });

    test('isUnlimited is true only for a zero limit', () {
      expect(Item(name: 'Gift', claimLimit: 0).isUnlimited, isTrue);
      expect(Item(name: 'Gift', claimLimit: 1).isUnlimited, isFalse);
      expect(Item(name: 'Gift', claimLimit: 3).isUnlimited, isFalse);
    });

    test(
      'hasClaimRoom follows the finite limit and ignores it when unlimited',
      () {
        final oneClaim = <String, DateTime>{'u1': claimedAt};
        final twoClaims = <String, DateTime>{'u1': claimedAt, 'u2': otherClaim};
        final threeClaims = <String, DateTime>{
          'u1': claimedAt,
          'u2': otherClaim,
          'u3': claimedAt,
        };

        expect(Item(name: 'Gift').hasClaimRoom, isTrue);
        expect(Item(name: 'Gift', claims: oneClaim).hasClaimRoom, isFalse);
        expect(
          Item(name: 'Gift', claimLimit: 3, claims: twoClaims).hasClaimRoom,
          isTrue,
        );
        expect(
          Item(name: 'Gift', claimLimit: 3, claims: threeClaims).hasClaimRoom,
          isFalse,
        );
        expect(
          Item(name: 'Gift', claimLimit: 0, claims: threeClaims).hasClaimRoom,
          isTrue,
        );
      },
    );

    test('isClaimedBy matches a stored uid, never a null or absent one', () {
      final item = Item(
        name: 'Gift',
        claims: <String, DateTime>{'u1': claimedAt},
      );

      expect(item.isClaimedBy('u1'), isTrue);
      expect(item.isClaimedBy('u2'), isFalse);
      expect(item.isClaimedBy(null), isFalse);
    });

    test(
      'toMap stores claims as ISO-8601 strings and always sets claimLimit',
      () {
        final item = Item(
          name: 'Gift',
          claims: <String, DateTime>{'u1': claimedAt},
          claimLimit: 0,
        );

        final map = item.toMap();

        expect(map['claims'], <String, dynamic>{
          'u1': claimedAt.toIso8601String(),
        });
        expect(map['claimLimit'], 0);
        expect(map.containsKey('claimedBy'), isFalse);
        expect(map.containsKey('claimedAt'), isFalse);
      },
    );

    test('toMap writes the empty defaults a new item carries', () {
      final map = Item(name: 'Gift').toMap();

      expect(map['claims'], isEmpty);
      expect(map['claimLimit'], 1);
    });

    test('fromMap round-trips toMap', () {
      final item = Item(
        id: 'item-1',
        name: 'Gift',
        description: 'Something they want',
        url: 'https://example.com/gift',
        claims: <String, DateTime>{'u1': claimedAt},
        claimLimit: 2,
      );

      final parsed = Item.fromMap(item.toMap(), 'item-1');

      expect(parsed.name, item.name);
      expect(parsed.description, item.description);
      expect(parsed.url, item.url);
      expect(parsed.claims, <String, DateTime>{'u1': claimedAt});
      expect(parsed.claimLimit, 2);
    });

    test('fromMap reads a missing, non-integer or negative limit as 1', () {
      for (final Object? limit in <Object?>[null, '2', -1, 1.5]) {
        final item = Item.fromMap(<String, dynamic>{
          'name': 'Gift',
          if (limit != null) 'claimLimit': limit,
        }, 'item-1');

        expect(item.claimLimit, 1, reason: 'claimLimit $limit');
      }
    });

    test('fromMap keeps a zero limit', () {
      expect(
        Item.fromMap(<String, dynamic>{
          'name': 'Gift',
          'claimLimit': 0,
        }, 'i').claimLimit,
        0,
      );
    });

    test('fromMap tolerates an absent or non-map claims field', () {
      expect(
        Item.fromMap(<String, dynamic>{'name': 'Gift'}, 'i').claims,
        isEmpty,
      );
      expect(
        Item.fromMap(<String, dynamic>{
          'name': 'Gift',
          'claims': 'nope',
        }, 'i').claims,
        isEmpty,
      );
    });

    test('fromMap drops a claim value that is not an ISO-8601 string', () {
      final item = Item.fromMap(<String, dynamic>{
        'name': 'Gift',
        'claims': <String, dynamic>{
          'u1': claimedAt.toIso8601String(),
          'u2': 'not-a-date',
          'u3': 7,
        },
      }, 'i');

      expect(item.claims.keys, orderedEquals(<String>['u1']));
      expect(item.claims['u1'], claimedAt);
    });

    test('copyWith keeps claims and claimLimit unless they are overridden', () {
      final item = Item(
        name: 'Gift',
        claims: <String, DateTime>{'u1': claimedAt},
        claimLimit: 2,
      );

      final renamed = item.copyWith(name: 'Renamed');
      expect(renamed.claims, item.claims);
      expect(renamed.claimLimit, 2);

      final limited = item.copyWith(claimLimit: 3);
      expect(limited.claims, item.claims);
      expect(limited.claimLimit, 3);
    });
  });
}
