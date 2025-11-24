class User {
  static const String collectionName = 'users';

  final String? id;
  final String? displayName;
  final String? email;
  final String? phoneNumber;

  User({this.id, this.displayName, this.email, this.phoneNumber});

  User copyWith({
    String? id,
    String? displayName,
    String? email,
    String? phoneNumber,
  }) {
    return User(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'phoneNumber': phoneNumber,
    };
  }

  factory User.fromMap(Map<String, dynamic> map, String id) {
    return User(
      id: id,
      displayName: map['displayName'],
      email: map['email'],
      phoneNumber: map['phoneNumber'],
    );
  }
}
