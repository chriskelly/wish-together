import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;
// import 'package:wishtogether/features/auth/data/auth_service.dart';

class LoginPage extends StatelessWidget {

  static const String route = '/login';

  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Welcome to WishTogether!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text('Sign in to continue'),
            const SizedBox(height: 40),
            // This button is rendered by the google_sign_in_web package
            // and initiates the sign-in flow.
            web_only.renderButton(),
          ],
        ),
      ),
    );
  }
}