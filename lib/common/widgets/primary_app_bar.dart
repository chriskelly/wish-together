import 'package:flutter/material.dart';

import 'package:wishtogether/core/design_tokens.dart';

/// The app bar the shared feature pages adopt as they are restyled.
///
/// [actions], [leading] and [automaticallyImplyLeading] are [AppBar]'s own
/// slots, forwarded unchanged and defaulting to [AppBar]'s values, so a bar
/// keeps whatever controls and back-arrow behaviour it would have had.
///
/// The 2px bottom rule is a [Border] on the app bar's own material, so it
/// paints over the bar's fill. A `DecoratedBox` around the bar would sit
/// *behind* that opaque material and never be visible.
class PrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const PrimaryAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: Text(title, style: theme.textTheme.headlineSmall),
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
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
