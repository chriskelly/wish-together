/// Input rules shared by the phone sign-in pages.
///
/// The phone field is US-only: the user types ten digits without a country
/// code, and the app adds `+1` before asking Firebase for a code. The code
/// field, in turn, only submits once it holds a six-digit SMS code.
library;

/// The separators a pasted phone number may carry. Everything else has to be a
/// digit, which is what keeps a plus sign, a letter or a slash out.
final RegExp _phoneSeparators = RegExp(r'[\s.\-()]');

/// A complete US number, after the separators are gone.
final RegExp _tenDigits = RegExp(r'^\d{10}$');

/// A complete SMS code, after surrounding whitespace is gone.
final RegExp _sixDigits = RegExp(r'^\d{6}$');

/// The E.164 form of ten-digit US phone number [input], or `null` when it is
/// not one.
///
/// Accepts the separators people paste from contacts and messages — spaces,
/// dashes, dots and parentheses — and ignores surrounding whitespace. A leading
/// `+` or an eleventh digit is rejected: the field asks for the number without
/// its country code, and treating either as valid would turn an ordinary typo
/// into a request for the wrong number.
String? normalizeUsPhoneNumber(String input) {
  final digits = input.replaceAll(_phoneSeparators, '');
  return _tenDigits.hasMatch(digits) ? '+1$digits' : null;
}

/// Whether [input] is a complete six-digit SMS code.
///
/// The code arrives from a keyboard, a paste or SMS autofill, so surrounding
/// whitespace is ignored before counting. Firebase's SMS codes are six digits.
bool isCompleteSmsCode(String input) => _sixDigits.hasMatch(input.trim());
