import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/app_update/domain/update_url.dart';

void main() {
  group('parseUpdateUrl', () {
    test('accepts an https App Store URL', () {
      // Arrange
      const raw = 'https://apps.apple.com/app/id1234567890';

      // Act
      final uri = parseUpdateUrl(raw);

      // Assert
      expect(uri, isNotNull);
      expect(uri?.scheme, 'https');
      expect(uri?.host, 'apps.apple.com');
    });

    test('accepts the native itms-apps scheme', () {
      // Arrange
      const raw = 'itms-apps://apps.apple.com/app/id1234567890';

      // Act
      final uri = parseUpdateUrl(raw);

      // Assert
      expect(uri, isNotNull);
      expect(uri?.scheme, 'itms-apps');
    });

    test('accepts an upper-case scheme', () {
      // Arrange
      const raw = 'HTTPS://apps.apple.com/app/id1234567890';

      // Act
      final uri = parseUpdateUrl(raw);

      // Assert
      expect(uri, isNotNull);
    });

    test('trims surrounding whitespace', () {
      // Arrange
      const raw = '  https://apps.apple.com/app/id1234567890  ';

      // Act
      final uri = parseUpdateUrl(raw);

      // Assert
      expect(uri, isNotNull);
    });

    test('rejects an empty value', () {
      // Arrange
      const raw = '';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects a whitespace-only value', () {
      // Arrange
      const raw = '   ';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects a relative path', () {
      // Arrange
      const raw = '/app/id1234567890';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects http', () {
      // Arrange
      const raw = 'http://apps.apple.com/app/id1234567890';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects a javascript URL', () {
      // Arrange
      const raw = 'javascript:alert(1)';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects a file URL', () {
      // Arrange
      const raw = 'file:///etc/passwd';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects a telephone URL', () {
      // Arrange
      const raw = 'tel:+15551234567';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects a scheme with no host', () {
      // Arrange
      const raw = 'https:';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });

    test('rejects malformed input', () {
      // Arrange
      const raw = 'not a url';

      // Act & Assert
      expect(parseUpdateUrl(raw), isNull);
    });
  });
}
