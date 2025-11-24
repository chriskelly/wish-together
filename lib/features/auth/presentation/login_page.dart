import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer' as developer;
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/google_sign_in_stub.dart'
    if (dart.library.html) 'package:google_sign_in_web/web_only.dart'
    as web_only;
import 'package:wishtogether/features/auth/presentation/verification_page.dart';

class LoginPage extends StatefulWidget {
  static const String route = '/login';

  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _authService = getIt<AuthService>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'Welcome to WishTogether!',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 20),
                const Text('Sign in to continue'),
                const SizedBox(height: 40),
                // This button is rendered by the google_sign_in_web package
                // and initiates the sign-in flow.
                web_only.renderButton(),
                const SizedBox(height: 20),
                _dividerBetweenOAuthAndPhone(),
                const SizedBox(height: 20),
                _phoneNumberInputField(),
                const SizedBox(height: 20),
                _requestVerificationCodeButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Row _dividerBetweenOAuthAndPhone() => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: Text('OR'),
      ),
      Expanded(child: Divider()),
    ],
  );

  TextField _phoneNumberInputField() => TextField(
    controller: _phoneController,
    decoration: const InputDecoration(
      labelText: 'Phone Number (e.g. 408 555 1234)',
      border: OutlineInputBorder(),
    ),
    keyboardType: TextInputType.phone,
  );

  ElevatedButton _requestVerificationCodeButton(
    BuildContext context,
  ) => ElevatedButton(
    onPressed: () async {
      // Automatically prepend the US country code
      final phoneNumber = '+1${_phoneController.text}';

      final redirectTo = GoRouterState.of(
        context,
      ).uri.queryParameters[redirectToParam];
      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          await _authService.signInWithPhoneCredential(credential);
          // ignore: use_build_context_synchronously
          if (context.mounted) {
            context.go(redirectTo ?? '/');
          }
        },
        verificationFailed: (e) {
          developer.log('Phone verification failed', error: e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Phone verification failed: ${e.message}'),
              ),
            );
          }
        },
        codeSent: (verificationId, forceResendingToken) {
          if (mounted) {
            final redirectTo = GoRouterState.of(
              context,
            ).uri.queryParameters[redirectToParam];
            final verifyUri = redirectTo != null
                ? '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(redirectTo)}'
                : VerificationPage.route;
            context.go(verifyUri, extra: verificationId);
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          developer.log(
            'Auto-retrieval timeout for verification ID: $verificationId',
          );
        },
      );
    },
    child: const Text('Send Verification Code'),
  );
}
