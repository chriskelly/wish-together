class User {
  static const String collectionName = 'users';

  final String? id;
  final String? displayName;
  final String? email;

  User({this.id, this.displayName, this.email});

  User copyWith({String? id, String? displayName, String? email}) {
    return User(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
    );
  }

  Map<String, dynamic> toMap() {
    return {'displayName': displayName, 'email': email};
  }

  factory User.fromMap(Map<String, dynamic> map, String id) {
    return User(id: id, displayName: map['displayName'], email: map['email']);
  }
}
