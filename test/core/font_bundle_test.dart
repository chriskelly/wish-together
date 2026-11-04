import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fontAssets = <String>[
  'assets/fonts/Archivo-Regular.ttf',
  'assets/fonts/Archivo-Bold.ttf',
  'assets/fonts/Archivo-ExtraBold.ttf',
  'assets/fonts/ArchivoBlack-Regular.ttf',
  'assets/fonts/Pacifico-Regular.ttf',
];

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('declares every bundled face', () {
    for (final asset in _fontAssets) {
      expect(
        pubspec,
        contains('asset: $asset'),
        reason: '$asset is not declared under flutter.fonts',
      );
    }

    expect(pubspec, contains('family: Archivo\n'));
    expect(pubspec, contains('family: Archivo Black\n'));
    expect(pubspec, contains('family: Pacifico\n'));
    expect(pubspec, contains('weight: 700'));
    expect(pubspec, contains('weight: 800'));
  });

  test('ships the font licence beside the faces', () {
    expect(pubspec, contains('- assets/fonts/OFL.txt'));
    expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
  });

  test('no longer depends on google_fonts', () {
    expect(
      RegExp(r'^\s*google_fonts:', multiLine: true).hasMatch(pubspec),
      isFalse,
      reason: 'every face is bundled, so a runtime font fetch would come back',
    );
  });

  test('every bundled file exists and is non-trivial', () {
    for (final asset in _fontAssets) {
      final file = File(asset);
      expect(file.existsSync(), isTrue, reason: '$asset is missing');
      expect(
        file.lengthSync(),
        greaterThan(10 * 1024),
        reason: '$asset looks like a placeholder or a failed download',
      );
    }
  });
}
