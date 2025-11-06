class Group {
  static const String collectionName = 'groups';

  final String? id;
  final String name;
  final String ownerId;
  final List<String> members;

  Group({
    this.id,
    required this.name,
    required this.ownerId,
    required this.members,
  });

  factory Group.fromMap(Map<String, dynamic> map, String id) {
    return Group(
      id: id,
      name: map['name'] ?? '',
      ownerId: map['ownerId'] ?? '',
      members: List<String>.from(map['members'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name, 'ownerId': ownerId, 'members': members};
  }

  Group copyWith({
    String? id,
    String? name,
    String? ownerId,
    List<String>? members,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      members: members ?? this.members,
    );
  }
}
