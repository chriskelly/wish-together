import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/app_urls.dart';

void main() {
  group('locationFromUniversalLink', () {
    test('maps a production join link to a location', () {
      expect(
        locationFromUniversalLink(
          Uri.parse('https://wishtogether.gift/join?group=abc'),
          allowedHosts: releaseUniversalLinkHosts,
        ),
        '/join?group=abc',
      );
    });

    test('preserves percent-encoding in the query', () {
      expect(
        locationFromUniversalLink(
          Uri.parse('https://wishtogether.gift/join?group=a%2Fb'),
          allowedHosts: releaseUniversalLinkHosts,
        ),
        '/join?group=a%2Fb',
      );
    });

    test('accepts group and wishlist paths', () {
      for (final path in ['/group/abc', '/wishlist/xyz']) {
        expect(
          locationFromUniversalLink(
            Uri.parse('https://wishtogether.gift$path'),
            allowedHosts: releaseUniversalLinkHosts,
          ),
          path,
        );
      }
    });

    test('rejects paths outside the AASA list', () {
      for (final path in [
        '/',
        '/privacy',
        '/support',
        '/joinXYZ',
        '/join/',
        '/group/',
        '/wishlist/',
      ]) {
        expect(
          locationFromUniversalLink(
            Uri.parse('https://wishtogether.gift$path'),
            allowedHosts: releaseUniversalLinkHosts,
          ),
          isNull,
        );
      }
    });

    test('rejects http, foreign hosts, and custom schemes', () {
      for (final uri in [
        Uri.parse('http://wishtogether.gift/join?group=abc'),
        Uri.parse('https://example.test/join?group=abc'),
        Uri.parse('wishtogether://join?group=abc'),
      ]) {
        expect(
          locationFromUniversalLink(
            uri,
            allowedHosts: releaseUniversalLinkHosts,
          ),
          isNull,
        );
      }
    });

    test('accepts the staging host only when it is allowed', () {
      final staging = Uri.parse(
        'https://wish-together-staging.web.app/join?group=abc',
      );
      expect(
        locationFromUniversalLink(
          staging,
          allowedHosts: debugUniversalLinkHosts,
        ),
        '/join?group=abc',
      );
      expect(
        locationFromUniversalLink(
          staging,
          allowedHosts: releaseUniversalLinkHosts,
        ),
        isNull,
      );
    });

    test('drops a fragment', () {
      expect(
        locationFromUniversalLink(
          Uri.parse('https://wishtogether.gift/join?group=abc#frag'),
          allowedHosts: releaseUniversalLinkHosts,
        ),
        '/join?group=abc',
      );
    });
  });

  group('host sets', () {
    test('release hosts match the invite origin', () {
      expect(releaseUniversalLinkHosts, contains(Uri.parse(appOrigin).host));
      expect(releaseUniversalLinkHosts, isNot(contains(stagingHost)));
    });

    test(
      'the debug selector adds staging and the release selector does not',
      () {
        expect(universalLinkHostsFor(debug: true), contains(stagingHost));
        expect(
          universalLinkHostsFor(debug: false),
          isNot(contains(stagingHost)),
        );
      },
    );
  });
}
