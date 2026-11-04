import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Brand values are allowed in `lib/core/design_tokens.dart` and nowhere else
/// in production code. `lib/dev/` is exempt: its banner is deliberately loud
/// and is never in the production bundle.
const _allowed = <String>['lib/core/design_tokens.dart'];
const _exemptPrefixes = <String>['lib/dev/'];

final _literal = RegExp(
  r'\bColors\.'
  r'|\bColor\s*\(\s*0[xX]'
  r'|\bColor\.from'
  r'|\bMaterialColor\s*\(',
);

const _code = 0;
const _lineComment = 1;
const _blockComment = 2;
const _string = 3;

const _slash = 0x2F;
const _star = 0x2A;
const _newline = 0x0A;
const _singleQuote = 0x27;
const _doubleQuote = 0x22;
const _backslash = 0x5C;
const _lowerR = 0x72;
const _upperR = 0x52;

/// Replaces every comment and string body with spaces, preserving newlines and
/// the line count. Code is the only thing left, so the literal scan cannot be
/// fooled by prose and cannot be hidden by an apostrophe in a comment.
String _codeOnly(String source) {
  final out = StringBuffer();
  var state = _code;
  var quote = 0;
  var triple = false;
  var raw = false;
  var index = 0;

  while (index < source.length) {
    final char = source.codeUnitAt(index);
    final next = index + 1 < source.length ? source.codeUnitAt(index + 1) : -1;

    switch (state) {
      case _lineComment:
        if (char == _newline) {
          out.write('\n');
          state = _code;
        } else {
          out.write(' ');
        }
        index++;

      case _blockComment:
        if (char == _star && next == _slash) {
          out.write('  ');
          index += 2;
          state = _code;
        } else {
          out.write(char == _newline ? '\n' : ' ');
          index++;
        }

      case _string:
        if (!raw && char == _backslash) {
          final escaped = index + 1 < source.length;
          out.write(escaped ? '  ' : ' ');
          index += escaped ? 2 : 1;
        } else if (triple &&
            char == quote &&
            index + 2 < source.length &&
            source.codeUnitAt(index + 1) == quote &&
            source.codeUnitAt(index + 2) == quote) {
          out.write('   ');
          index += 3;
          state = _code;
        } else if (!triple && char == quote) {
          out.write(' ');
          index++;
          state = _code;
        } else {
          out.write(char == _newline ? '\n' : ' ');
          index++;
        }

      default:
        final isComment = char == _slash;
        if (isComment && next == _slash) {
          out.write('  ');
          index += 2;
          state = _lineComment;
        } else if (isComment && next == _star) {
          out.write('  ');
          index += 2;
          state = _blockComment;
        } else if (char == _singleQuote || char == _doubleQuote) {
          quote = char;
          triple =
              index + 2 < source.length &&
              source.codeUnitAt(index + 1) == char &&
              source.codeUnitAt(index + 2) == char;
          raw =
              index > 0 &&
              (source.codeUnitAt(index - 1) == _lowerR ||
                  source.codeUnitAt(index - 1) == _upperR);
          final length = triple ? 3 : 1;
          out.write(triple ? '   ' : ' ');
          index += length;
          state = _string;
        } else {
          out.writeCharCode(char);
          index++;
        }
    }
  }

  return out.toString();
}

/// The literal-bearing lines of [source], numbered from one.
List<(int, String)> _offendersIn(String source) {
  final lines = _codeOnly(source).split('\n');
  final offenders = <(int, String)>[];
  for (var index = 0; index < lines.length; index++) {
    if (_literal.hasMatch(lines[index])) {
      offenders.add((index + 1, lines[index].trim()));
    }
  }
  return offenders;
}

void main() {
  group('the scanner itself', () {
    test('sees a literal in code', () {
      const source = '''
const a = Colors.red;
const b = Color(0XFFB32234);
const c = Color.fromARGB(255, 0, 0, 0);
const d = MaterialColor(0xFFB32234, <int, Color>{});
''';

      expect(_offendersIn(source), hasLength(4));
    });

    test('ignores literals in comments and strings', () {
      const source = """
// Colors.red in a line comment
/* Color(0xFF000000) in a block comment */
/// The brand's palette mentions Color(0xFFB32234) in prose.
const label = 'Colors.red';
const other = "Color(0xFFFFFFFF)";
const raw = r'Color(0xFFB32234)';
final code = Colors.blue; // Color(0xFF000000)
""";

      final offenders = _offendersIn(source);

      expect(offenders, hasLength(1));
      expect(offenders.single.$2, contains('Colors.blue'));
    });

    test('two apostrophes across comments do not hide code between them', () {
      const source = """
// The brand's palette is fixed.
const hidden = Colors.red;
// ListTile's ink needs a Material.
""";

      expect(_offendersIn(source), hasLength(1));
    });

    test('an apostrophe in a comment does not hide the next line', () {
      const source = """
// The card's shadow is a light-mode device.
const hidden = Colors.red;
""";

      expect(_offendersIn(source), hasLength(1));
    });
  });

  test('production code carries no colour literals', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (_allowed.contains(entity.path) ||
          _exemptPrefixes.any(entity.path.startsWith)) {
        continue;
      }
      for (final (line, text) in _offendersIn(entity.readAsStringSync())) {
        offenders.add('${entity.path}:$line: $text');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use a ColorScheme role or a design token instead of a literal:\n'
          '${offenders.join('\n')}',
    );
  });
}
