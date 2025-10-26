import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

import 'router.dart';
import 'theme.dart';

void main() {
  runApp(const WishTogetherApp());
}

class WishTogetherApp extends StatefulWidget {
  const WishTogetherApp({super.key});

  @override
  State<WishTogetherApp> createState() => _WishTogetherAppState();
}

class _WishTogetherAppState extends State<WishTogetherApp> {
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    WidgetsFlutterBinding.ensureInitialized();

    final defaultOptions = DefaultFirebaseOptions.currentPlatform;

    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: defaultOptions.apiKey,
        appId: defaultOptions.appId,
        messagingSenderId: defaultOptions.messagingSenderId,
        projectId: defaultOptions.projectId,
        authDomain: 'wish-together-project.web.app',
        storageBucket: defaultOptions.storageBucket,
      ),
    );

    // Activate Firebase App Check with the CORRECT 'webProvider' parameter.
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaEnterpriseProvider('6LfN0vUrAAAAAIBImzC6j6Cu2WypCi7Ke_Wx3Xl8'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text(
                  'Error initializing app: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.done) {
          return MaterialApp.router(
            routerConfig: router,
            title: 'WishTogether',
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.system,
          );
        }

        return const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}
