class Item {
  static const String collectionName = 'items';

  final String? id;
  final String name;
  final String? description;
  final String? url;
  final String? claimedBy; // User ID of the person who claimed the item
  final DateTime? claimedAt;

  Item({
    this.id,
    required this.name,
    this.description,
    this.url,
    this.claimedBy,
    this.claimedAt,
  });

  Item copyWith({
    String? id,
    String? name,
    String? description,
    String? url,
    String? claimedBy,
    DateTime? claimedAt,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
      claimedBy: claimedBy ?? this.claimedBy,
      claimedAt: claimedAt ?? this.claimedAt,
    );
  }

  factory Item.fromMap(Map<String, dynamic> map, String id) {
    return Item(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] as String?,
      url: map['url'] as String?,
      claimedBy: map['claimedBy'] as String?,
      claimedAt: map['claimedAt'] == null
          ? null
          : DateTime.parse(map['claimedAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'url': url,
      'claimedBy': claimedBy,
      'claimedAt': claimedAt?.toIso8601String(),
    };
  }
}
