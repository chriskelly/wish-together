import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Wishlist.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Wishlist(
      id: doc.id,
      name: data['name'] ?? '',
      ownerId: data['ownerId'] ?? '',
      sharedWithGroups: List<String>.from(data['sharedWithGroups'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'ownerId': ownerId,
      'sharedWithGroups': sharedWithGroups,
    };
  }
}
