import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The production entrypoint: the only file a release build compiles.
const String productionEntrypoint = 'lib/main.dart';

/// Where dev-only code lives.
const String devDirectory = 'lib/dev/';

/// Packages a production bundle must never contain.
const List<String> productionForbiddenPackages = <String>[
  'package:fake_cloud_firestore/',
];

/// Files under `lib/dev/` allowed to touch a real Firebase, and why.
///
/// Fake mode has no project, no credentials and no network. Live mode exists to
/// have all three, so exactly one file composes it. Each entry is checked to
/// exist below, so renaming that file cannot silently widen the exception.
const Map<String, String> firebaseExceptions = <String, String>{
  'lib/dev/live_dev_session.dart':
      'the live backend: initializeApp and the custom-token sign-in',
};

/// Firebase singletons a fake-mode session must never reach.
///
/// `cloud_firestore` itself is allowed: a fixture stores its claim as the
/// `Timestamp` type the repository casts to. What is forbidden is touching a
/// real instance, which is what would initialise a project.
final RegExp realFirebaseUse = RegExp(
  r'Firebase\.initializeApp\s*\(|'
  r'Firebase(?:App|Auth|Firestore|AppCheck|RemoteConfig)\.instance',
);

void main() {
  test('the production entrypoint never reaches lib/dev', () {
    // ACT
    final graph = importGraphFrom(productionEntrypoint);

    // ASSERT: absence is structural, not a flag the tree-shaker has to honour.
    expect(
      graph.files.where((path) => path.startsWith(devDirectory)),
      isEmpty,
      reason: 'lib/main.dart must import nothing under lib/dev/',
    );
    expect(
      graph.packages.where(
        (uri) => productionForbiddenPackages.any(uri.startsWith),
      ),
      isEmpty,
      reason: 'a production bundle must not contain the in-memory fake store',
    );
  });

  test('only the live backend initialises Firebase', () {
    // ARRANGE
    final offenders = <String>[];

    // ACT
    for (final entity in Directory(devDirectory).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (realFirebaseUse.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }

    // ASSERT: fake mode has no project, no credentials and no network, so the
    // only file allowed to reach a real Firebase is the live composition.
    expect(
      offenders.where((path) => !firebaseExceptions.containsKey(path)),
      isEmpty,
      reason:
          'only firebaseExceptions may touch a real Firebase; fake mode must '
          'not',
    );
    expect(
      offenders,
      isNotEmpty,
      reason:
          'the scan must actually find the live backend; an empty scan would '
          'prove nothing',
    );
    for (final path in firebaseExceptions.keys) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path no longer exists: update firebaseExceptions',
      );
    }
  });
}

/// Every `lib/` file reachable from [entry], plus the third-party packages it
/// imports.
class ImportGraph {
  ImportGraph();

  final Set<String> files = <String>{};
  final Set<String> packages = <String>{};
}

/// Walks `import`/`export` directives from [entry].
///
/// Only files under `lib/` are opened; a `package:` import is recorded by name
/// so a forbidden package is visible without resolving it.
ImportGraph importGraphFrom(String entry) {
  final graph = ImportGraph();
  final pending = <String>[entry];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!graph.files.add(path)) {
      continue;
    }
    for (final uri in directivesOf(path)) {
      if (uri.startsWith('dart:')) {
        continue;
      }
      if (uri.startsWith('package:wishtogether/')) {
        pending.add('lib/${uri.substring('package:wishtogether/'.length)}');
        continue;
      }
      if (uri.startsWith('package:')) {
        graph.packages.add(uri);
        continue;
      }
      pending.add(resolveRelative(path, uri));
    }
  }
  return graph;
}

/// The import and export targets of one file.
Iterable<String> directivesOf(String path) {
  final source = File(path).readAsStringSync();
  return RegExp(
    '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
    multiLine: true,
  ).allMatches(source).map((match) => match.group(1)!);
}

/// Resolves [relative] against the directory holding [from].
String resolveRelative(String from, String relative) {
  final segments = from.split('/')..removeLast();
  for (final part in relative.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(part);
  }
  return segments.join('/');
}
