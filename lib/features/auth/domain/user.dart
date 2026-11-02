class User {
  static const String collectionName = 'users';

  final String? id;
  final String? displayName;
  final String? email;
  final String? phoneNumber;

  User({this.id, this.displayName, this.email, this.phoneNumber});

  /// Whether [value] is a display name at all: non-null, with content once
  /// surrounding whitespace is ignored.
  ///
  /// The one definition of "a name", shared by the profile form validator and
  /// [hasDisplayName], so neither can accept a name the other rejects.
  static bool isNonBlankName(String? value) =>
      value?.trim().isNotEmpty ?? false;

  /// Whether the user has a display name, which is what the router treats as
  /// "onboarded".
  ///
  /// Whitespace is not a name. The save use case trims and rejects a blank one,
  /// so a stored value with no content came from outside the app; treating it as
  /// no name returns that user to the profile form, where the value is prefilled,
  /// rather than letting them through with an invisible name.
  bool get hasDisplayName => isNonBlankName(displayName);

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
