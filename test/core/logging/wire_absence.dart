import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/log_record.dart';

/// Fails when any wire value on [records] carries one of [sensitive].
///
/// `log_record_test.dart` proves the allowed *keys*; this proves a sensitive
/// *value* cannot ride along inside one of them. Each seam calls it with the
/// same three shapes — a phone number, a document id and the Remote Config
/// `update_message` text — so a new field on any event is checked everywhere.
///
/// [records] must not be empty: an absence assertion over nothing proves
/// nothing, so a seam that stopped recording would fail here rather than pass
/// silently.
void expectNoSensitiveValues(
  Iterable<LogRecord> records,
  Iterable<String> sensitive,
) {
  expect(records, isNotEmpty);
  for (final record in records) {
    for (final entry in record.toMap().entries) {
      for (final value in sensitive) {
        expect(
          '${entry.value}',
          isNot(contains(value)),
          reason: '${entry.key} leaked a sensitive value',
        );
      }
    }
  }
}
