import 'package:cloud_firestore/cloud_firestore.dart';

class Item {
  final String? id;
  final String name;
  final String? description;
  final String? url;
  final String? claimedBy; // User ID of the person who claimed the item
  final Timestamp? claimedAt;

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
    Timestamp? claimedAt,
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

  factory Item.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Item(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] as String?,
      url: data['url'] as String?,
      claimedBy: data['claimedBy'] as String?,
      claimedAt: data['claimedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'url': url,
      'claimedBy': claimedBy,
      'claimedAt': claimedAt,
    };
  }
}
