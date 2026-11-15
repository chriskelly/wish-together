import 'package:flutter/material.dart';
import 'package:wishtogether/core/design_tokens.dart';

/// A titled section with an add action and one child.
///
/// A page whose providers own the reads pairs it with `ListContentBuilder`.
class DataSection extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;

  /// The add button's tooltip. Each call site writes the exact string its users
  /// see, so the section stays non-generic.
  final String addTooltip;
  final Widget child;

  const DataSection({
    super.key,
    required this.title,
    required this.onAdd,
    required this.addTooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The display face and its tracking come from the type scale.
            Text(title, style: theme.textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: theme.colorScheme.primary,
              onPressed: onAdd,
              tooltip: addTooltip,
            ),
          ],
        ),
        const SizedBox(height: BrandGeometry.spacingSm),
        child,
      ],
    );
  }
}
