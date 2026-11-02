import 'package:wishtogether/dev/fixtures/dev_fixture.dart';

/// The viewer of the `empty` scenario.
const String emptyViewerUid = 'emp-u1';

/// A signed-in account with nothing in it.
///
/// This is the new-user state: no wishlists, no groups, no items. It shows both
/// of home's empty sections and the not-found path a list route takes for an id
/// the fixture does not seed, without the noise of seed data.
///
/// The `users/` document is not optional: the router sends a signed-in user with
/// no display name to onboarding, so an account with no document never reaches
/// the screens this scenario is for.
final DevFixture emptyFixture = DevFixture(
  id: 'empty',
  viewerUid: emptyViewerUid,
  documents: <String, Map<String, dynamic>>{
    'users/$emptyViewerUid': <String, dynamic>{'displayName': 'Ada Empty'},
  },
);
