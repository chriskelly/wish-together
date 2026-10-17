import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';

void main() {
  group('shouldShowAppleSignInButton', () {
    test('shows on native iOS', () {
      expect(
        shouldShowAppleSignInButton(isWeb: false, platform: TargetPlatform.iOS),
        isTrue,
      );
    });

    test('hides on iOS Safari, where web resolves to the browser OS', () {
      expect(
        shouldShowAppleSignInButton(isWeb: true, platform: TargetPlatform.iOS),
        isFalse,
      );
    });

    test('hides on Android', () {
      expect(
        shouldShowAppleSignInButton(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('hides on web regardless of the browser OS', () {
      expect(
        shouldShowAppleSignInButton(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('hides on macOS', () {
      expect(
        shouldShowAppleSignInButton(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
    });
  });
}
