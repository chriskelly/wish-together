import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer' as developer;

import '../data/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number (e.g. 408 555 1234)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // Automatically prepend the US country code
                final phoneNumber = '+1${_phoneController.text}';
                
                await _authService.verifyPhoneNumber(
                  phoneNumber: phoneNumber,
                  verificationCompleted: (credential) async {
                    await _authService.signInWithCredential(credential);
                    // ignore: use_build_context_synchronously
                    context.go('/');
                  },
                  verificationFailed: (e) {
                    developer.log('Phone verification failed', error: e);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Phone verification failed: ${e.message}')),
                    );
                  },
                  codeSent: (verificationId, forceResendingToken) {
                    context.go('/verify', extra: verificationId);
                  },
                  codeAutoRetrievalTimeout: (verificationId) {
                    developer.log('Auto-retrieval timeout for verification ID: $verificationId');
                  },
                );
              },
              child: const Text('Send Verification Code'),
            ),
          ],
        ),
      ),
    );
  }
}
