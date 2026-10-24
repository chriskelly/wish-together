import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';

void main() {
  test('builds the canonical production invite path off web', () {
    expect(
      GroupDetailsPage.getInvitationLink('123'),
      'https://wishtogether.gift/join?group=123',
    );
  });

  test('uses the supplied origin and encodes the group id', () {
    expect(
      GroupDetailsPage.getInvitationLink('a b', origin: 'https://preview.test'),
      'https://preview.test/join?group=a+b',
    );
  });
}
