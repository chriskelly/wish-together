import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
}
