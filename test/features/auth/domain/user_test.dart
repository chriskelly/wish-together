import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

void main() {
  group('User.hasDisplayName', () {
    test('is false when the user has no display name', () {
      final user = User(id: 'user-1');

      expect(user.hasDisplayName, isFalse);
    });

    test('is false when the display name is empty', () {
      final user = User(id: 'user-1', displayName: '');

      expect(user.hasDisplayName, isFalse);
    });

    test('is false when the display name is only whitespace', () {
      final user = User(id: 'user-1', displayName: ' \t\n ');

      expect(user.hasDisplayName, isFalse);
    });

    test('is true when the display name has content', () {
      const name = 'Grace Hopper';
      final user = User(id: 'user-1', displayName: name);

      expect(user.hasDisplayName, isTrue);
    });

    test('ignores whitespace around a display name that has content', () {
      const name = 'Grace Hopper';
      final user = User(id: 'user-1', displayName: '  $name  ');

      expect(user.hasDisplayName, isTrue);
    });
  });
}
