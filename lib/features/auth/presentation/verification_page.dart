import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/phone_auth_error.dart';

class VerificationPage extends StatefulWidget {
  static const String route = '/verify';

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

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Code')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _codeInputField(),
                const SizedBox(height: 20),
                _verifyButton(),
              ],
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

  ElevatedButton _verifyButton() => ElevatedButton(
    onPressed: () async {
      try {
        await _authService.confirmPhoneCode(
          verificationId: widget.verificationId,
          smsCode: _codeController.text,
        );
        if (mounted) {
          context.go(widget.redirectTo ?? '/');
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(phoneAuthErrorMessage(e))));
        }
      }
    },
    child: const Text('Verify'),
  );
}
