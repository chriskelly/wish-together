import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';

import '../logging/recording_sink.dart';
import '../logging/wire_absence.dart';

class TestModel {
  final String? id;
  final String name;

  TestModel({this.id, required this.name});
}

class TestModelRepository extends FirebaseRepository<TestModel> {
  TestModelRepository(super.collectionPath, {super.firestore});

  @override
  TestModel fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TestModel(id: doc.id, name: data['name']);
  }

  @override
  Map<String, dynamic> toFirestore(TestModel model) {
    return {'name': model.name};
  }
}

class FailingModelRepository extends TestModelRepository {
  FailingModelRepository(
    super.collectionPath, {
    super.firestore,
    required this.error,
  });

  final Object error;

  @override
  TestModel fromFirestore(DocumentSnapshot doc) => throw error;
}

/// Fails before any Firestore call, to pin a write path's guard.
class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    throw StateError('write failed');
  }
}

void main() {
  group('FirebaseRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late TestModelRepository repository;

    const String testCollectionPath = 'test_models';
    const String nameField = 'name';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      repository = TestModelRepository(
        testCollectionPath,
        firestore: fakeFirestore,
      );
    });

    test('add should add a document to the collection', () async {
      const testName = 'Test Name';
      final model = TestModel(name: testName);

      final docRef = await repository.add(model);

      final doc = await fakeFirestore
          .collection(testCollectionPath)
          .doc(docRef.id)
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?[nameField], testName);
    });

    test('update should overwrite a document in the collection', () async {
      const oldName = 'Old Name';
      const newName = 'New Name';

      final docRef = await fakeFirestore.collection(testCollectionPath).add({
        nameField: oldName,
      });
      final model = TestModel(id: docRef.id, name: newName);

      await repository.update(docRef.id, model);

      final doc = await fakeFirestore
          .collection(testCollectionPath)
          .doc(docRef.id)
          .get();
      expect(doc.data()?[nameField], newName);
    });

    test('updateData should partially update a document', () async {
      const originalName = 'Original Name';
      const extraValue = 'some value';
      const updatedName = 'Partially Updated';
      const extraField = 'extraField';

      final docRef = await fakeFirestore.collection(testCollectionPath).add({
        nameField: originalName,
        extraField: extraValue,
      });

      await repository.updateData(docRef.id, {nameField: updatedName});

      final doc = await fakeFirestore
          .collection(testCollectionPath)
          .doc(docRef.id)
          .get();
      expect(doc.data()?[nameField], updatedName);
      expect(doc.data()?[extraField], extraValue);
    });

    test('delete should remove a document from the collection', () async {
      const toDeleteName = 'To Delete';
      final docRef = await fakeFirestore.collection(testCollectionPath).add({
        nameField: toDeleteName,
      });

      var doc = await fakeFirestore
          .collection(testCollectionPath)
          .doc(docRef.id)
          .get();
      expect(doc.exists, isTrue);

      await repository.delete(docRef.id);

      doc = await fakeFirestore
          .collection(testCollectionPath)
          .doc(docRef.id)
          .get();
      expect(doc.exists, isFalse);
    });

    test('get should retrieve a single document', () async {
      const toGetName = 'To Get';
      final docRef = await fakeFirestore.collection(testCollectionPath).add({
        nameField: toGetName,
      });

      final model = await repository.get(docRef.id);

      expect(model, isNotNull);
      expect(model.id, docRef.id);
      expect(model.name, toGetName);
    });

    test(
      'streamOne should return a stream of a document and its updates',
      () async {
        const streamName = 'Stream Name';
        const updatedStreamName = 'Updated Stream Name';
        final docRef = await fakeFirestore.collection(testCollectionPath).add({
          nameField: streamName,
        });

        final stream = repository.streamOne(docRef.id);

        expectLater(
          stream,
          emitsInOrder([
            isA<TestModel>().having((m) => m.name, nameField, streamName),
            isA<TestModel>().having(
              (m) => m.name,
              nameField,
              updatedStreamName,
            ),
          ]),
        );

        await Future.delayed(Duration.zero);

        await fakeFirestore
            .collection(testCollectionPath)
            .doc(docRef.id)
            .update({nameField: updatedStreamName});
      },
    );

    test('streamAll should return a stream of all documents', () async {
      const firstModelName = 'First Stream';
      const secondModelName = 'Second Stream';
      await fakeFirestore.collection(testCollectionPath).add({
        nameField: firstModelName,
      });
      await fakeFirestore.collection(testCollectionPath).add({
        nameField: secondModelName,
      });

      final stream = repository.streamAll();
      final models = await stream.first;

      expect(models.length, 2);
      expect(models.any((m) => m.name == firstModelName), isTrue);
      expect(models.any((m) => m.name == secondModelName), isTrue);
    });

    test('streamWhere should return a filtered stream of documents', () async {
      const noMatchName = 'No Match';
      const matchName = 'Match';
      await fakeFirestore.collection(testCollectionPath).add({
        nameField: noMatchName,
      });
      await fakeFirestore.collection(testCollectionPath).add({
        nameField: matchName,
      });

      final stream = repository.streamWhere(nameField, isEqualTo: matchName);
      final models = await stream.first;

      expect(models.length, 1);
      expect(models.first.name, matchName);
    });
  });

  group('FirebaseRepository diagnostics', () {
    const String nestedPath = 'wishlists/some-id/items';

    late FakeFirebaseFirestore fakeFirestore;
    late RecordingSink sink;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      addTearDown(getIt.reset);
    });

    TestModelRepository nestedRepository() =>
        TestModelRepository(nestedPath, firestore: fakeFirestore);

    FailingModelRepository throwingRepository() => FailingModelRepository(
      nestedPath,
      firestore: fakeFirestore,
      error: TypeError(),
    );

    test('reports the collection name, never the document path', () async {
      await expectLater(
        nestedRepository().get('missing'),
        throwsA(isA<TypeError>()),
      );

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.collection, 'items');
      expect(event.op, FirestoreOp.get);
    });

    test('reports a structured error code', () async {
      const code = 'permission-denied';
      final repository = FailingModelRepository(
        nestedPath,
        firestore: fakeFirestore,
        error: const CodedError(code),
      );

      await expectLater(repository.get('missing'), throwsA(isA<CodedError>()));

      expect(sink.eventsOf<FirestoreErrorEvent>().single.code, code);
    });

    test('does not report a successful one-shot list', () async {
      await expectLater(
        nestedRepository().listWhere('name', isEqualTo: 'x'),
        completes,
      );

      expect(sink.eventsOf<FirestoreErrorEvent>(), isEmpty);
    });

    test('does not report a successful one-shot get or write', () async {
      final repository = nestedRepository();

      final docRef = await repository.add(TestModel(name: 'x'));
      await repository.get(docRef.id);
      await repository.delete(docRef.id);

      expect(sink.eventsOf<FirestoreErrorEvent>(), isEmpty);
    });

    test('a failed nested read carries no id or sensitive value', () async {
      // Arrange: the item id is in the path, and the error is code-shaped.
      const itemId = 'item-7f3a9c1d2e';
      const phoneNumber = '+15555550123';
      const updateMessageToken = 'MAINTENANCE-WINDOW-42';
      final repository = FailingModelRepository(
        'wishlists/wl-1/items',
        firestore: fakeFirestore,
        error: const CodedError('unavailable'),
      );

      // Act
      await expectLater(repository.get(itemId), throwsA(isA<CodedError>()));

      // Assert
      expectNoSensitiveValues(sink.records, <String>[
        phoneNumber,
        itemId,
        updateMessageToken,
      ]);
    });

    test('rethrows the original failure unchanged', () async {
      Object? caught;
      try {
        await throwingRepository().get('missing');
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<TypeError>());
      expect(sink.eventsOf<FirestoreErrorEvent>(), hasLength(1));
    });

    test('reports a failed partial update as a write', () async {
      final repository = TestModelRepository(
        nestedPath,
        firestore: ThrowingFirestore(),
      );

      await expectLater(
        repository.updateData('missing', {'name': 'x'}),
        throwsA(isA<StateError>()),
      );

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.op, FirestoreOp.write);
      expect(event.collection, 'items');
    });

    test('streamAll reports and forwards a mapping failure', () async {
      await fakeFirestore.collection(nestedPath).add({'name': 'x'});
      final stream = throwingRepository().streamAll();

      await expectLater(stream, emitsError(isA<TypeError>()));

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.collection, 'items');
      expect(event.op, FirestoreOp.list);
    });

    test('streamWhere reports and forwards a mapping failure', () async {
      await fakeFirestore.collection(nestedPath).add({'name': 'x'});
      final stream = throwingRepository().streamWhere('name', isEqualTo: 'x');

      await expectLater(stream, emitsError(isA<TypeError>()));

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.collection, 'items');
      expect(event.op, FirestoreOp.list);
    });

    test('streamOne reports and forwards a mapping failure', () async {
      final stream = throwingRepository().streamOne('missing');

      await expectLater(stream, emitsError(isA<TypeError>()));

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.collection, 'items');
      expect(event.op, FirestoreOp.get);
    });
  });
}
