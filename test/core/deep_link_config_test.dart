import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/app_urls.dart';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _hosting(String path) =>
    _json(path)['hosting'] as Map<String, dynamic>;

/// Both hosting configs must satisfy this contract, so they cannot drift.
void _expectHostingContract(String path) {
  final hosting = _hosting(path);
  expect(hosting['appAssociation'], 'NONE');

  final headers = (hosting['headers'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final aasa = headers.firstWhere(
    (h) => h['source'] == '/.well-known/apple-app-site-association',
  );
  final aasaHeaders = (aasa['headers'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  expect(
    aasaHeaders.any(
      (h) => h['key'] == 'Content-Type' && h['value'] == 'application/json',
    ),
    isTrue,
  );

  final sources = (hosting['rewrites'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map((r) => r['source'])
      .toList();
  expect(sources, ['/privacy', '/support', '**']);
}

void main() {
  test('AASA is narrow, names the app, and matches the Dart path rule', () {
    final details =
        (_json('web/.well-known/apple-app-site-association')['applinks']
                as Map<String, dynamic>)['details']
            as List<dynamic>;
    final entry = details.single as Map<String, dynamic>;
    expect(entry['appIDs'], contains('CD8XP2U645.gift.wishtogether'));
    final components = (entry['components'] as List<dynamic>)
        .map((c) => (c as Map<String, dynamic>)['/'] as String)
        .toSet();
    expect(components, {'/join', '/group/*', '/wishlist/*'});
    for (final component in components) {
      final sample = component.replaceAll('*', 'sample');
      expect(isUniversalLinkPath(sample), isTrue, reason: component);
    }
  });

  test('firebase.json disables Hosting AASA generation and types the file', () {
    _expectHostingContract('firebase.json');
  });

  test(
    'firebase.staging.json disables Hosting AASA generation and types the file',
    () {
      _expectHostingContract('firebase.staging.json');
    },
  );

  test('entitlements split production and staging and keep existing keys', () {
    final release = File('ios/Runner/Runner.entitlements').readAsStringSync();
    final debug = File('ios/Runner/Runner-Debug.entitlements')
        .readAsStringSync();

    expect(release, contains('<string>applinks:wishtogether.gift</string>'));
    expect(release, isNot(contains('wish-together-staging')));
    expect(release, contains('<key>aps-environment</key>'));
    expect(release, contains('<key>com.apple.developer.applesignin</key>'));

    expect(
      debug,
      contains('<string>applinks:wish-together-staging.web.app</string>'),
    );
    expect(debug, isNot(contains('applinks:wishtogether.gift</string>')));
    expect(debug, contains('<key>aps-environment</key>'));
    expect(debug, contains('<key>com.apple.developer.applesignin</key>'));
  });

  test('the engine deep-link handler is disabled', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')
          .hasMatch(plist),
      isTrue,
    );
  });
  test('signing wiring selects the right entitlements per configuration', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();

    expect(
      'CODE_SIGN_ENTITLEMENTS = Runner/Runner-Debug.entitlements;'
          .allMatches(pbxproj)
          .length,
      1,
    );
    expect(
      'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
          .allMatches(pbxproj)
          .length,
      2,
    );
  });

  test('the AASA app id matches the team and Runner bundle id', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    final team = RegExp(r'DEVELOPMENT_TEAM = ([A-Z0-9]+);')
        .firstMatch(pbxproj)!
        .group(1)!;
    final bundle = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(pbxproj)
        .map((match) => match.group(1)!)
        .firstWhere((id) => !id.contains('RunnerTests'));

    final details =
        (_json('web/.well-known/apple-app-site-association')['applinks']
                as Map<String, dynamic>)['details']
            as List<dynamic>;
    expect(
      (details.single as Map<String, dynamic>)['appIDs'],
      contains('$team.$bundle'),
    );
  });
}
