import 'package:flutter/widgets.dart';

/// The non-web fallback for `google_sign_in_web`'s `renderButton`.
///
/// `login_page.dart` resolves `web_only` to this file unless the build is for
/// web, so its `web_only.renderButton()` reference compiles on every platform.
/// The web build resolves it to the real package; `AuthService` always imports
/// the real `google_sign_in` package.
Widget renderButton() => const SizedBox.shrink();
