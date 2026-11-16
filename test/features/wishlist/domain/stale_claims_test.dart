import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/stale_claims.dart';

void main() {
  final now = DateTime.utc(2026, 11, 16, 12);
  final staleAt = now.subtract(const Duration(days: 200));
  final recentAt = now.subtract(const Duration(days: 30));

  Item item(String? id, Map<String, DateTime> claims) =>
      Item(id: id, name: 'Gift', claims: claims, claimLimit: 2);

  group('StaleClaimsPlan.fromItems', () {
    test('a claim exactly 183 days old is not stale', () {
      final plan = StaleClaimsPlan.fromItems(
        [item('item-1', {'uid-1': now.subtract(const Duration(days: 183))})],
        now: now,
      );

      expect(plan.isEmpty, isTrue);
    });

    test('a claim one second older than 183 days is stale', () {
      final plan = StaleClaimsPlan.fromItems(
        [
          item('item-1', {
            'uid-1': now
                .subtract(const Duration(days: 183))
                .subtract(const Duration(seconds: 1)),
          }),
        ],
        now: now,
      );

      expect(plan.byItem, {'item-1': {'uid-1'}});
    });

    test('a recent claim on the same item is never part of the plan', () {
      final plan = StaleClaimsPlan.fromItems(
        [item('item-1', {'old': staleAt, 'recent': recentAt})],
        now: now,
      );

      expect(plan.byItem, {'item-1': {'old'}});
    });

    test('a future-dated claim is not stale', () {
      final plan = StaleClaimsPlan.fromItems(
        [item('item-1', {'uid-1': now.add(const Duration(days: 1))})],
        now: now,
      );

      expect(plan.isEmpty, isTrue);
    });

    test('an item with no claims is absent', () {
      final plan = StaleClaimsPlan.fromItems([item('item-1', {})], now: now);

      expect(plan.isEmpty, isTrue);
    });

    test('an item without an id is skipped', () {
      final plan = StaleClaimsPlan.fromItems(
        [item(null, {'uid-1': staleAt})],
        now: now,
      );

      expect(plan.isEmpty, isTrue);
    });

    test('a later clock makes the same claim stale', () {
      final claimAt = now.subtract(const Duration(days: 100));
      final today = StaleClaimsPlan.fromItems(
        [item('item-1', {'uid-1': claimAt})],
        now: now,
      );
      final later = StaleClaimsPlan.fromItems(
        [item('item-1', {'uid-1': claimAt})],
        now: now.add(const Duration(days: 100)),
      );

      expect(today.isEmpty, isTrue);
      expect(later.byItem, {'item-1': {'uid-1'}});
    });
  });
}
