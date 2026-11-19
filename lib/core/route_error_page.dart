import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Material chrome for a location that matches no route.
///
/// go_router 18's automatic error page is a bare `ErrorScreen` when the app
/// mounts Flutter's `MaterialApp`, because go_router looks for `material_ui`'s
/// `MaterialApp`. The router supplies this page explicitly through
/// `errorPageBuilder`, so an unknown link still gets a scaffold and app bar.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SelectableText(error?.toString() ?? 'page not found'),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Home'),
            ),
          ],
        ),
      ),
    );
  }
}
