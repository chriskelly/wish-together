import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/session_context.dart';

void main() {
  group('sessionIdFromBytes', () {
    test('encodes 16 zero bytes as 26 Crockford symbols', () {
      const expected = '00000000000000000000000000';
      final bytes = List<int>.filled(16, 0);

      final sessionId = sessionIdFromBytes(bytes);

      expect(sessionId, expected);
    });

    test('encodes the last symbol with zero padding', () {
      const expected = 'ZZZZZZZZZZZZZZZZZZZZZZZZZW';
      final bytes = List<int>.filled(16, 0xff);

      final sessionId = sessionIdFromBytes(bytes);

      expect(sessionId, expected);
    });

    test('encodes a byte sequence in most-significant-bit-first order', () {
      const expected = '000G40R40M30E209185GR38E1W';
      final bytes = List<int>.generate(16, (index) => index);

      expect(sessionIdFromBytes(bytes), expected);
    });
  });

  group('supportCodeFor', () {
    test('takes the first six symbols of the session id', () {
      const sessionId = 'ABCDEFGHJKMNPQRSTVWXYZ0123';
      const expected = 'ABCDEF';

      expect(supportCodeFor(sessionId), expected);
    });

    test('never contains the Crockford-ambiguous letters I, L, O or U', () {
      final ambiguous = RegExp('[ILOU]');
      final random = Random(7);

      for (var run = 0; run < 20; run++) {
        final id = sessionIdFromBytes(
          List<int>.generate(16, (_) => random.nextInt(256)),
        );
        final supportCode = supportCodeFor(id);

        expect(supportCode.length, 6);
        expect(supportCode, isNot(matches(ambiguous)));
        expect(id, isNot(matches(ambiguous)));
      }
    });
  });

  group('userRefForUid', () {
    test('keeps the first 12 lowercase hex characters of the sha256', () {
      const uid = 'uid-123';
      const expected = '23481502b488';

      expect(userRefForUid(uid), expected);
      expect(userRefForUid(uid), matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('is stable for one uid', () {
      const uid = 'family-uid-000000000000001';
      const expected = '8a13aeaf468b';

      final first = userRefForUid(uid);
      final second = userRefForUid(uid);

      expect(second, first);
      expect(first, expected);
    });

    test('differs between uids', () {
      const first = 'family-uid-000000000000001';
      const second = 'uid_beta';

      expect(userRefForUid(first), isNot(userRefForUid(second)));
    });
  });

  group('resolveBuildId', () {
    test('falls back to dev when the build define is empty', () {
      expect(resolveBuildId(''), devBuildId);
      expect(resolveBuildId('   '), devBuildId);
    });

    test('keeps a real build id and trims it', () {
      const build = '53';

      expect(resolveBuildId(build), build);
      expect(resolveBuildId('  $build '), build);
    });
  });

  group('SessionContext.create', () {
    test('mints a fresh 26-symbol session id with a matching support code', () {
      final first = SessionContext.create(platform: 'web', random: Random(1));
      final second = SessionContext.create(platform: 'web', random: Random(2));

      expect(first.sessionId.length, 26);
      expect(first.supportCode, supportCodeFor(first.sessionId));
      expect(first.supportCode.length, 6);
      expect(first.sessionId, isNot(second.sessionId));
    });

    test('starts signed out on the root route', () {
      final session = SessionContext.create(platform: 'ios', random: Random(3));

      expect(session.userRef, isNull);
      expect(session.route, '/');
      expect(session.platform, 'ios');
    });

    test('resolves the build from the define when none is passed', () {
      final session = SessionContext.create(platform: 'web', random: Random(4));

      expect(session.build, resolveBuildId(wtBuildId));
    });

    test('redacts a route that carries an id', () {
      final session = SessionContext.create(
        platform: 'web',
        route: '/wishlist/abc123',
        random: Random(5),
      );

      expect(session.route, '/wishlist/:id');
    });
  });

  group('SessionContext.withUserRef', () {
    test('replaces and then clears the user ref', () {
      const context = SessionContext(
        sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
        supportCode: 'ABCDEF',
        build: '53',
        platform: 'ios',
      );
      const userRef = '23481502b488';

      final signedIn = context.withUserRef(userRef);

      expect(signedIn.userRef, userRef);
      expect(signedIn.withUserRef(null).userRef, isNull);
    });

    test('ignores a value that is not a derived reference', () {
      const context = SessionContext(
        sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
        supportCode: 'ABCDEF',
        build: '53',
        platform: 'ios',
      );
      const rawUid = 'abc123DEF456ghi789JKL012mno3';

      expect(context.withUserRef(rawUid).userRef, isNull);
    });
  });

  group('SessionContext.withRoute', () {
    test('redacts ids when it replaces the route', () {
      const context = SessionContext(
        sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
        supportCode: 'ABCDEF',
        build: '53',
        platform: 'ios',
      );

      expect(context.withRoute('/group/abc123').route, '/group/:id');
    });
  });

  group('SessionContext equality', () {
    SessionContext context({
      String id = '0123456789ABCDEFGHJKMNPQRST',
      String route = '/',
      String? userRef,
    }) => SessionContext(
      sessionId: id,
      supportCode: supportCodeFor(id),
      build: '57',
      platform: 'ios',
      userRef: userRef,
      route: route,
    );

    test('equal fields make equal contexts', () {
      expect(context(), equals(context()));
      expect(context().hashCode, context().hashCode);
    });

    test('a changed field makes contexts unequal', () {
      expect(context(route: '/'), isNot(equals(context(route: '/join'))));
      expect(
        context(userRef: userRefForUid('a')),
        isNot(equals(context(userRef: userRefForUid('b')))),
      );
    });
  });
}
