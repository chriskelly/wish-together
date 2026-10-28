import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to print: S1's console sink.
const String consoleSinkPath = 'lib/core/logging/log_sink.dart';

/// Matches every way `lib/` could write to the console without the facade.
///
/// `debugPrintStack` is a different symbol but the same leak channel: its
/// label is free text, and the only site interpolated an error. `developer.log`
/// is the same story one level up — its `error:` argument is a raw exception,
/// and the auth pages used it to print what the sink already reported.
final RegExp directDebugOutput = RegExp(
  r'\bdebugPrint(?:Stack)?\s*\(|\bdeveloper\.log\s*\(',
);

void main() {
  test('lib/ reports through the facade, never the console', () {
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
      if (directDebugOutput.hasMatch(entity.readAsStringSync())) {
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
