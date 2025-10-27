import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String? displayName;
  final String? phoneNumber;

  AppUser({required this.id, this.displayName, this.phoneNumber});

  AppUser copyWith({String? id, String? displayName, String? phoneNumber}) {
    return AppUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return {'displayName': displayName, 'phoneNumber': phoneNumber};
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AppUser(
      id: doc.id,
      displayName: data['displayName'],
      phoneNumber: data['phoneNumber'],
    );
  }
}
