import 'package:wishtogether/features/wishlist/domain/item.dart';

/// How old a claim must be before the owner's cleanup treats it as left over
/// from a previous season.
const Duration staleClaimAge = Duration(days: 183);

/// The human-readable form of [staleClaimAge] used by the banner and its
/// confirmation.
const String staleClaimAgeLabel = '6 months';

/// The old claims an owner can clear, keyed by item id.
///
/// A claim is stale when it is strictly older than [staleClaimAge] at the
/// supplied clock. The plan is a snapshot: it does not re-read the items.
class StaleClaimsPlan {
  const StaleClaimsPlan(this.byItem);

  /// A plan with nothing to clear.
  static const StaleClaimsPlan empty = StaleClaimsPlan(<String, Set<String>>{});

  /// Classifies [items] against [staleClaimAge] at [now].
  factory StaleClaimsPlan.fromItems(
    Iterable<Item> items, {
    required DateTime now,
  }) {
    final cutoff = now.subtract(staleClaimAge);
    final byItem = <String, Set<String>>{};

    for (final item in items) {
      final id = item.id;
      if (id == null) {
        continue;
      }

      Set<String>? stale;
      for (final entry in item.claims.entries) {
        if (entry.value.isBefore(cutoff)) {
          (stale ??= <String>{}).add(entry.key);
        }
      }
      if (stale != null) {
        byItem[id] = stale;
      }
    }

    return StaleClaimsPlan(byItem);
  }

  /// The stale claim uids for each item that has any.
  final Map<String, Set<String>> byItem;

  bool get isEmpty => byItem.isEmpty;
}
