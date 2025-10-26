import 'package:cloud_firestore/cloud_firestore.dart';

class Group {
  final String id;
  final String name;
  final String ownerId;
  final List<String> members;

  Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
  });

  // Factory constructor to create a Group from a Firestore document
  factory Group.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Group(
      id: doc.id,
      name: data['name'] ?? '',
      ownerId: data['ownerId'] ?? '',
      // Ensure members is a list of strings
      members: List<String>.from(data['members'] ?? []),
    );
  }

  // Method to convert a Group instance to a map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'ownerId': ownerId,
      'members': members,
    };
  }
}
