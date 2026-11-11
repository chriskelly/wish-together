import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/data/phone_input.dart';

void main() {
  group('normalizeUsPhoneNumber', () {
    test('adds the US country code to ten bare digits', () {
      // Act
      final number = normalizeUsPhoneNumber('4085551234');

      // Assert
      expect(number, '+14085551234');
    });

    test('accepts the separators people paste, and drops them', () {
      // Arrange
      const formattedNumbers = <String>[
        '408 555 1234',
        '408-555-1234',
        '408.555.1234',
        '(408) 555-1234',
      ];

      // Act
      final normalized = formattedNumbers.map(normalizeUsPhoneNumber).toList();

      // Assert
      for (var index = 0; index < formattedNumbers.length; index++) {
        expect(
          normalized[index],
          '+14085551234',
          reason: formattedNumbers[index],
        );
      }
    });

    test('ignores whitespace around the number', () {
      // Act
      final number = normalizeUsPhoneNumber('  408 555 1234 \n');

      // Assert
      expect(number, '+14085551234');
    });

    test('rejects a leading plus, even with the country code', () {
      // Act
      final withCountryCode = normalizeUsPhoneNumber('+14085551234');
      final withSeparators = normalizeUsPhoneNumber('+1 408 555 1234');

      // Assert
      expect(withCountryCode, isNull);
      expect(withSeparators, isNull);
    });

    test('rejects an eleven-digit number', () {
      // Act
      final withCountryCode = normalizeUsPhoneNumber('14085551234');
      final separated = normalizeUsPhoneNumber('1 408 555 1234');
      final withoutCountryCode = normalizeUsPhoneNumber('40855512345');

      // Assert
      expect(withCountryCode, isNull);
      expect(separated, isNull);
      expect(withoutCountryCode, isNull);
    });

    test('rejects a short number', () {
      // Act
      final short = normalizeUsPhoneNumber('408555123');

      // Assert
      expect(short, isNull);
    });

    test('rejects letters and symbols the field does not expect', () {
      // Act
      final letters = normalizeUsPhoneNumber('408CALLNOW');
      final slashes = normalizeUsPhoneNumber('408/555/1234');

      // Assert
      expect(letters, isNull);
      expect(slashes, isNull);
    });

    test('rejects an empty or whitespace-only field', () {
      // Act
      final empty = normalizeUsPhoneNumber('');
      final whitespace = normalizeUsPhoneNumber('   ');

      // Assert
      expect(empty, isNull);
      expect(whitespace, isNull);
    });
  });

  group('isCompleteSmsCode', () {
    test('accepts exactly six digits', () {
      // Act
      final complete = isCompleteSmsCode('123456');

      // Assert
      expect(complete, isTrue);
    });

    test('ignores whitespace around the code', () {
      // Act
      final complete = isCompleteSmsCode(' 123456 ');

      // Assert
      expect(complete, isTrue);
    });

    test('rejects an empty, short or long code', () {
      // Act
      final empty = isCompleteSmsCode('');
      final short = isCompleteSmsCode('12345');
      final long = isCompleteSmsCode('1234567');

      // Assert
      expect(empty, isFalse);
      expect(short, isFalse);
      expect(long, isFalse);
    });

    test('rejects anything that is not all digits', () {
      // Act
      final complete = isCompleteSmsCode('12345a');

      // Assert
      expect(complete, isFalse);
    });
  });
}
