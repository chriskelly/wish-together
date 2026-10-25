import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/redaction.dart';

void main() {
  group('redactRoute', () {
    test('keeps the root and literal-only routes', () {
      const root = '/';
      const login = '/login';

      expect(redactRoute(root), root);
      expect(redactRoute(login), login);
    });

    test('replaces a wishlist id with the :id placeholder', () {
      const pattern = '/wishlist/:id';

      expect(redactRoute('/wishlist/abc123'), pattern);
    });

    test('replaces a group id and keeps the edit suffix', () {
      const pattern = '/group/:id/edit';

      expect(redactRoute('/group/abc123/edit'), pattern);
    });

    test('handles the nested item routes', () {
      const addItem = '/wishlist/:id/add-item';
      const editItem = '/wishlist/:id/item/:id/edit';

      expect(redactRoute('/wishlist/w1/add-item'), addItem);
      expect(redactRoute('/wishlist/w1/item/i1/edit'), editItem);
    });

    test('keeps paths that are already patterns', () {
      const pattern = '/wishlist/:id';

      expect(redactRoute(pattern), pattern);
    });

    test('drops the query string so an invite id never leaks', () {
      const join = '/join';

      expect(redactRoute('/join?group=abc123'), join);
    });

    test('drops a fragment', () {
      const root = '/';

      expect(redactRoute('/#/join'), root);
    });

    test('maps an empty location to the root', () {
      const root = '/';

      expect(redactRoute(''), root);
    });

    test('masks an unlisted area as well as its ids', () {
      const pattern = '/:id/:id';

      expect(redactRoute('/settings/dark'), pattern);
    });

    test('masks a bare id-shaped location', () {
      const pattern = '/:id';

      expect(redactRoute('/abc123'), pattern);
    });

    test('treats a trailing slash like the same route', () {
      const pattern = '/wishlist/:id';

      expect(redactRoute('/wishlist/abc123/'), pattern);
    });
  });

  group('redactCollection', () {
    test('keeps an allowlisted collection name', () {
      const collection = 'items';

      expect(redactCollection(collection), collection);
    });

    test('masks a collection path, which could carry a document id', () {
      const masked = unknownCollection;

      expect(redactCollection('wishlists/abc123/items'), masked);
    });

    test('masks an empty collection name', () {
      expect(redactCollection(''), unknownCollection);
    });
  });

  group('redactCode', () {
    test('keeps a well-shaped Firebase code', () {
      const code = 'permission-denied';

      expect(redactCode(code), code);
    });

    test('keeps an uppercase platform code', () {
      const code = 'ERROR_OPERATION_NOT_SUPPORTED';

      expect(redactCode(code), code);
    });

    test('keeps a one-word code shorter than an id', () {
      const code = 'unauthenticated';

      expect(redactCode(code), code);
    });

    test('drops text that is shaped like a message', () {
      const message = 'Verification failed for Jane Doe';

      expect(redactCode(message), isNull);
    });

    test('drops an email-shaped value', () {
      const email = 'jane@example.com';

      expect(redactCode(email), isNull);
    });

    test('drops a bare uid-shaped token', () {
      const uid = 'abc123DEF456ghi789JKL012mno3';

      expect(redactCode(uid), isNull);
    });

    test('drops a bare Firestore-id-shaped token', () {
      const documentId = 'AbCdEfGhIjKlMnOpQrSt';

      expect(redactCode(documentId), isNull);
    });

    test('drops a bare phone-number-shaped value', () {
      const phoneNumber = '15551234567';

      expect(redactCode(phoneNumber), isNull);
    });

    test('drops a punctuated phone-number-shaped value', () {
      expect(redactCode('555-1234'), isNull);
      expect(redactCode('555.1234'), isNull);
      expect(redactCode('555-123-4567'), isNull);
    });

    test('drops a dotted lowercase name-like value', () {
      const name = 'jane.doe';

      expect(redactCode(name), isNull);
    });

    test('drops an empty or overlong value', () {
      final tooLong = List.filled(65, 'a').join();

      expect(redactCode(''), isNull);
      expect(redactCode(tooLong), isNull);
    });

    test('passes null through', () {
      expect(redactCode(null), isNull);
    });
  });
}
