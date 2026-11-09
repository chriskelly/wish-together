class Item {
  static const String collectionName = 'items';

  final String? id;
  final String name;
  final String? description;
  final String? url;

  /// The people who claimed this item, keyed by uid.
  ///
  /// One entry per person: the map value is when they claimed, which is kept
  /// for support and ordering but is never shown. The model stores times as
  /// [DateTime]; only `ItemRepository` converts them at the Firestore boundary.
  final Map<String, DateTime> claims;

  /// How many people may claim this item. `1` is the classic single claim,
  /// `0` is unlimited and `n > 1` allows n claimants. A document without the
  /// field reads as `1`.
  final int claimLimit;

  Item({
    this.id,
    required this.name,
    this.description,
    this.url,
    this.claims = const {},
    this.claimLimit = 1,
  }) : assert(claimLimit >= 0, 'claimLimit cannot be negative');

  int get claimCount => claims.length;

  bool get isUnlimited => claimLimit == 0;

  bool get hasClaimRoom => isUnlimited || claimCount < claimLimit;

  bool isClaimedBy(String? uid) => uid != null && claims.containsKey(uid);

  Item copyWith({
    String? id,
    String? name,
    String? description,
    String? url,
    Map<String, DateTime>? claims,
    int? claimLimit,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
      claims: claims ?? this.claims,
      claimLimit: claimLimit ?? this.claimLimit,
    );
  }

  /// Reads a stored item map.
  ///
  /// A claim value that is not an ISO-8601 string is dropped rather than
  /// failing the read: one bad stored value must not hide the whole list. The
  /// migration's `--verify` is what reports such a document.
  factory Item.fromMap(Map<String, dynamic> map, String id) {
    final rawClaims = map['claims'];
    final claims = <String, DateTime>{};
    if (rawClaims is Map) {
      for (final entry in rawClaims.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String) {
          continue;
        }
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          claims[key] = parsed;
        }
      }
    }

    final rawLimit = map['claimLimit'];
    return Item(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] as String?,
      url: map['url'] as String?,
      claims: claims,
      claimLimit: rawLimit is int && rawLimit >= 0 ? rawLimit : 1,
    );
  }

  /// The stored shape. Claim times cross as ISO-8601 strings for the same
  /// reason the old claim date did: this map is handed to Firestore after
  /// `ItemRepository` turns each value into a `Timestamp`.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'url': url,
      'claims': <String, dynamic>{
        for (final entry in claims.entries)
          entry.key: entry.value.toIso8601String(),
      },
      'claimLimit': claimLimit,
    };
  }
}
