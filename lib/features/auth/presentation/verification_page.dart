import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/common/widgets/support_code_tile.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/phone_auth_error.dart';
import 'package:wishtogether/features/auth/data/phone_input.dart';

class VerificationPage extends StatefulWidget {
  static const String route = '/verify';

  /// Shown when the page outlives the sign-in it was opened for, so there is
  /// nothing left to confirm.
  static const String expiredSignInMessage =
      'This sign-in has expired. Go back and request a new code.';

  final String verificationId;
  final String? redirectTo;

  const VerificationPage({
    super.key,
    required this.verificationId,
    this.redirectTo,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _codeController = TextEditingController();
  final _authService = getIt<AuthService>();

  /// Whether a confirmation is in flight.
  ///
  /// The button stays disabled until the platform reports an outcome, so a
  /// second tap cannot confirm the same code twice.
  bool _verifying = false;

  @override
  void dispose() {
    // Leaving this page abandons a web sign-in whose code was never entered;
    // dropping it stops a later confirmation reusing the number the user
    // backed out of. Native keeps nothing pending, and a successful sign-in has
    // already consumed its confirmation, so both reach this as a no-op.
    _authService.discardPendingPhoneSignIn();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supportCode = appLogOrNull?.session.supportCode;
    return Scaffold(
      // Login opens this page with push, so the AppBar has an implied leading
      // action back to the number the user entered.
      appBar: const PrimaryAppBar(title: 'Verify Code'),
      body: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewport.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _codeInputField(),
                      const SizedBox(height: 20),
                      _verifyButton(),
                      if (supportCode != null) ...[
                        const SizedBox(height: 24),
                        // A wrong or expired code is a failure the user has to
                        // report, so the code has to be readable here and not
                        // only on the page they came from.
                        SupportCodeTile(supportCode: supportCode),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextField _codeInputField() => TextField(
    controller: _codeController,
    decoration: const InputDecoration(
      labelText: 'Verification Code',
      border: OutlineInputBorder(),
    ),
    keyboardType: TextInputType.number,
  );

  Widget _verifyButton() => ListenableBuilder(
    listenable: _codeController,
    builder: (context, _) => ElevatedButton(
      // A six-digit code is the shape Firebase sends. Anything else is a tap
      // that can only fail, so the button stays disabled rather than sending a
      // request the service has to reject as `missing-verification-code`.
      onPressed: !_verifying && isCompleteSmsCode(_codeController.text)
          ? _verify
          : null,
      child: const Text('Verify'),
    ),
  );

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    // The button is disabled for both cases, but a tap already dispatched
    // against the previous build still reaches this handler.
    if (_verifying || !isCompleteSmsCode(code)) {
      return;
    }
    setState(() => _verifying = true);
    try {
      await _authService.confirmPhoneCode(
        verificationId: widget.verificationId,
        smsCode: code,
      );
      if (mounted) {
        context.go(widget.redirectTo ?? '/');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(phoneAuthErrorMessage(e))));
      }
    } on StateError {
      // The page can outlive the web sign-in it was opened for, because
      // browser history can bring it back after the user returned to login.
      // There is nothing to confirm by then, and the tap must say so rather
      // than fail silently.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VerificationPage.expiredSignInMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }
}
