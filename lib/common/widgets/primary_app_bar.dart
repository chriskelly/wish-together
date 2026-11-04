import 'package:flutter/material.dart';

import 'package:wishtogether/core/design_tokens.dart';

/// The app bar every feature page adopts.
///
/// The 2px bottom rule is a [Border] on the app bar's own material, so it
/// paints over the bar's fill. A `DecoratedBox` around the bar would sit
/// *behind* that opaque material and never be visible.
class PrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const PrimaryAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: Text(title, style: theme.textTheme.headlineSmall),
      shape: Border(
        bottom: BorderSide(
          color: theme.colorScheme.outline,
          width: BrandGeometry.borderWidth,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
