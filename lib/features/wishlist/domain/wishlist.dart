class Wishlist {
  final String? id;
  final String name;
  final String ownerId;
  final List<String> sharedWithGroups;

  Wishlist({
    this.id,
    required this.name,
    required this.ownerId,
    this.sharedWithGroups = const [],
  });

  Wishlist copyWith({
    String? id,
    String? name,
    String? ownerId,
    List<String>? sharedWithGroups,
  }) {
    return Wishlist(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      sharedWithGroups: sharedWithGroups ?? this.sharedWithGroups,
    );
  }

  factory Wishlist.fromMap(Map<String, dynamic> map, String id) {
    return Wishlist(
      id: id,
      name: map['name'] ?? '',
      ownerId: map['ownerId'] ?? '',
      sharedWithGroups: List<String>.from(map['sharedWithGroups'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerId': ownerId,
      'sharedWithGroups': sharedWithGroups,
    };
  }
}
