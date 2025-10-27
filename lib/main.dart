import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() async {
  // Ensure Flutter bindings are initialized before any Firebase services.
  WidgetsFlutterBinding.ensureInitialized();

  // Use the standard Firebase initialization with the generated options.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAppCheck.instance.activate(
    providerWeb: ReCaptchaEnterpriseProvider('6LfN0vUrAAAAAIBImzC6j6Cu2WypCi7Ke_Wx3Xl8'),
  );

  runApp(const WishTogetherApp());
}

class WishTogetherApp extends StatelessWidget {
  const WishTogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      title: 'WishTogether',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
    );
  }
}
