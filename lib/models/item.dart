import 'package:cloud_firestore/cloud_firestore.dart';

class Item {
  final String? id;
  final String name;
  final String? description;
  final String? link;

  Item({
    this.id,
    required this.name,
    this.description,
    this.link,
  });

  Item copyWith({
    String? id,
    String? name,
    String? description,
    String? link,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      link: link ?? this.link,
    );
  }

  factory Item.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Item(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] as String?,
      link: data['link'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'link': link,
    };
  }
}
