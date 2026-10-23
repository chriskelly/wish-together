import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/firestore_target.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

void main() {
  group('resolveFirestoreDatabaseId', () {
    test('targets the default database when the build flag is absent', () {
      expect(resolveFirestoreDatabaseId(''), defaultFirestoreDatabaseId);
    });

    test('treats whitespace as the default database', () {
      expect(resolveFirestoreDatabaseId('   '), defaultFirestoreDatabaseId);
    });

    test('accepts an explicit default database id', () {
      expect(
        resolveFirestoreDatabaseId(defaultFirestoreDatabaseId),
        defaultFirestoreDatabaseId,
      );
    });

    test('keeps a named database id', () {
      const namedDatabase = 'staging';

      expect(resolveFirestoreDatabaseId(namedDatabase), namedDatabase);
    });

    test('trims surrounding whitespace from a named id', () {
      const namedDatabase = 'staging';

      expect(resolveFirestoreDatabaseId('  $namedDatabase  '), namedDatabase);
    });

    test('rejects a database resource path', () {
      expect(
        () => resolveFirestoreDatabaseId('projects/p/databases/staging'),
        throwsArgumentError,
      );
    });

    test('rejects an id containing whitespace', () {
      expect(() => resolveFirestoreDatabaseId('stag ing'), throwsArgumentError);
    });

    test('rejects an uppercase id', () {
      expect(() => resolveFirestoreDatabaseId('Staging'), throwsArgumentError);
    });

    test('rejects an id shorter than the Firestore minimum', () {
      expect(() => resolveFirestoreDatabaseId('abc'), throwsArgumentError);
    });

    test('accepts a hyphenated id', () {
      const hyphenatedId = 'staging-2';

      expect(resolveFirestoreDatabaseId(hyphenatedId), hyphenatedId);
    });

    test('keeps the build define in sync with the deploy target', () {
      const expected = String.fromEnvironment('WT_FIRESTORE_DATABASE_EXPECTED');
      if (expected.isEmpty) {
        // Normal test runs do not pin a target; the staging deploy sets both
        // defines from the same firebase.staging.json value.
        return;
      }

      expect(firestoreDatabaseIdOverride, expected);
      expect(firestoreTargetStamp, '$firestoreTargetStampPrefix$expected');
    });
  });

  group('selectFirestoreInstance', () {
    late MockFirebaseFirestore defaultInstance;

    setUp(() {
      defaultInstance = MockFirebaseFirestore();
    });

    test('uses the default instance when no target is set', () {
      String? namedId;

      final result = selectFirestoreInstance(
        override: '',
        defaultInstance: defaultInstance,
        namedInstance: (id) {
          namedId = id;
          return MockFirebaseFirestore();
        },
      );

      expect(result, same(defaultInstance));
      expect(namedId, isNull);
    });

    test('forwards the build target to the named instance', () {
      final named = MockFirebaseFirestore();
      String? requestedId;

      final result = createFirestoreInstance(
        override: 'staging',
        defaultInstance: defaultInstance,
        namedInstance: (id) {
          requestedId = id;
          return named;
        },
      );

      expect(result, same(named));
      expect(requestedId, 'staging');
    });

    test('uses the default instance for the explicit default id', () {
      final result = selectFirestoreInstance(
        override: defaultFirestoreDatabaseId,
        defaultInstance: defaultInstance,
        namedInstance: (_) => MockFirebaseFirestore(),
      );

      expect(result, same(defaultInstance));
    });

    test('does not need the default instance for a named target', () {
      final named = MockFirebaseFirestore();

      final result = selectFirestoreInstance(
        override: 'staging',
        defaultInstance: null,
        namedInstance: (_) => named,
      );

      expect(result, same(named));
    });

    test('uses the named instance for a named target', () {
      final namedInstance = MockFirebaseFirestore();
      String? requestedId;

      final result = selectFirestoreInstance(
        override: 'staging',
        defaultInstance: defaultInstance,
        namedInstance: (id) {
          requestedId = id;
          return namedInstance;
        },
      );

      expect(result, same(namedInstance));
      expect(requestedId, 'staging');
    });

    test('rejects an invalid id before creating an instance', () {
      var created = false;

      expect(
        () => selectFirestoreInstance(
          override: 'Staging',
          defaultInstance: defaultInstance,
          namedInstance: (_) {
            created = true;
            return MockFirebaseFirestore();
          },
        ),
        throwsArgumentError,
      );
      expect(created, isFalse);
    });
  });
}
