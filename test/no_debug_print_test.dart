import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to print: S1's console sink.
const String consoleSinkPath = 'lib/core/logging/log_sink.dart';

void main() {
  test('lib/ reports through the facade instead of debugPrint', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      scanned++;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == consoleSinkPath) {
        continue;
      }
      if (entity.readAsStringSync().contains('debugPrint(')) {
        offenders.add(path);
      }
    }

    expect(
      scanned,
      greaterThan(50),
      reason:
          'the scan must actually find lib/ sources (it runs from the '
          'package root; a silent empty scan would prove nothing)',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'Report through AppLog instead; $consoleSinkPath owns the only '
          'authorised call sites (its two debugPrint calls).',
    );
  });
}
