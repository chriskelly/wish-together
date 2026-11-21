import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The navigation extra is not part of the URL: go_router's history codec
/// cannot serialise a leave guard or a domain object, so a restored page can be
/// rebuilt with no extra. Reading it directly is what crashed WISH-TOGETHER-F
/// (`lib/core/router.dart` builder, a null-check on the create route's extra).
///
/// This scan is a backstop, not a proof: a local variable can launder the read,
/// and a null assertion on a local that holds a `routeExtra` result is not
/// caught. `routeExtra` in the exempt file is the only sanctioned access.
const String _exempt = 'lib/core/route_state.dart';

final RegExp _directRead = RegExp(r'\.extra\b');
final RegExp _nullChecked = RegExp(r'routeExtra<[^;]+?>\s*\([^)]*\)\s*!(?!=)');

/// The offences in one source file; kept separate so the scanner can be tested
/// against fixtures of its own.
List<String> extraOffences(String path, String source) {
  if (path.replaceAll('\\', '/') == _exempt) {
    return const <String>[];
  }
  final offences = <String>[];
  // A Sentry event also has an `extra` field; only route-state files are
  // governed by this invariant.
  if (source.contains('GoRouterState') && _directRead.hasMatch(source)) {
    offences.add('$path reads GoRouterState.extra directly');
  }
  if (_nullChecked.hasMatch(source)) {
    offences.add('$path null-checks a routeExtra result');
  }
  return offences;
}

void main() {
  test('route extras are read only through routeExtra', () {
    final offenders = <String>[];
    var scanned = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      scanned++;
      offenders.addAll(extraOffences(entity.path, entity.readAsStringSync()));
    }

    expect(
      scanned,
      greaterThan(50),
      reason: 'Run from the repository root; an empty scan is not a pass.',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'Read navigation extras through routeExtra and fall back when it '
          'returns null; a restore drops the extra and a direct cast throws.',
    );
  });

  group('the scanner itself', () {
    test('reports a direct extra read', () {
      final offences = extraOffences(
        'lib/routes.dart',
        'void build(GoRouterState state) { final extra = state.extra; }',
      );

      expect(offences, hasLength(1));
    });

    test('reports an immediately null-checked routeExtra result', () {
      final offences = extraOffences(
        'lib/routes.dart',
        'final args = routeExtra<CreateItemRouteArgs>(state)!;',
      );

      expect(offences, hasLength(1));
    });

    test('reports a null-checked nested generic', () {
      final offences = extraOffences(
        'lib/routes.dart',
        'routeExtra<Map<String, Object?>>(state)!',
      );

      expect(offences, hasLength(1));
    });

    test('allows a null test', () {
      expect(
        extraOffences('lib/routes.dart', 'routeExtra<Foo>(state) != null'),
        isEmpty,
      );
    });

    test('ignores an extra field that is not route state', () {
      expect(
        extraOffences('lib/log.dart', 'final extra = event.extra;'),
        isEmpty,
      );
    });

    test('exempts the helper file', () {
      expect(
        extraOffences(
          'lib/core/route_state.dart',
          'final extra = state.extra;',
        ),
        isEmpty,
      );
    });

    test('normalises a Windows path before the exemption check', () {
      expect(
        extraOffences(
          r'lib\core\route_state.dart',
          'final extra = state.extra;',
        ),
        isEmpty,
      );
    });
  });
}
