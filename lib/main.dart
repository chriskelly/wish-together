import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'firebase_options.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();
  final router = createRouter(authService);

  runApp(WishTogetherApp(authService: authService, router: router));
}

class WishTogetherApp extends StatelessWidget {
  final AuthService authService;
  final GoRouter router;

  const WishTogetherApp({
    super.key,
    required this.authService,
    required this.router,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        StreamProvider<User?>(
          create: (context) => authService.authStateChanges,
          initialData: null,
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        title: 'WishTogether',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
      ),
    );
  }
}