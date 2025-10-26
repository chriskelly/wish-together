import 'package:cloud_firestore/cloud_firestore.dart';

class Wishlist {
  final String id;
  final String name;
  final String ownerId;

  Wishlist({
    required this.id,
    required this.name,
    required this.ownerId,
  });

  // Factory constructor to create a Wishlist from a Firestore document
  factory Wishlist.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Wishlist(
      id: doc.id,
      name: data['name'] ?? '',
      ownerId: data['ownerId'] ?? '',
    );
  }

  // Method to convert a Wishlist instance to a map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'ownerId': ownerId,
    };
  }
}

class Item {
  final String id;
  final String name;
  final String description;
  final String link;
  final bool isPurchased;

  Item({
    required this.id,
    required this.name,
    this.description = '',
    this.link = '',
    this.isPurchased = false,
  });

  // Factory constructor to create an Item from a Firestore document
  factory Item.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Item(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      link: data['link'] ?? '',
      isPurchased: data['isPurchased'] ?? false,
    );
  }

  // Method to convert an Item instance to a map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'link': link,
      'isPurchased': isPurchased,
    };
  }
}
