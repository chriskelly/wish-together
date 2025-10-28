class User {
  final String? id;
  final String? displayName;
  final String? phoneNumber;

  User({this.id, this.displayName, this.phoneNumber});

  User copyWith({String? id, String? displayName, String? phoneNumber}) {
    return User(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  Map<String, dynamic> toMap() {
    return {'displayName': displayName, 'phoneNumber': phoneNumber};
  }

  factory User.fromMap(Map<String, dynamic> map, String id) {
    return User(
      id: id,
      displayName: map['displayName'],
      phoneNumber: map['phoneNumber'],
    );
  }
}
