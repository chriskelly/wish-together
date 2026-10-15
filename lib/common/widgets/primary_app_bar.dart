import 'package:flutter/material.dart';

class PrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const PrimaryAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
