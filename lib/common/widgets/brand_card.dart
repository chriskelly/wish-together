import 'package:flutter/material.dart';

import 'package:wishtogether/core/design_tokens.dart';

/// A card with the brand's 2px outline and hard offset shadow.
///
/// The shadow lives on an outer [Container] because `CardThemeData` can express
/// the colour, radius and side but not a zero-blur offset. The inner [Card] is
/// what keeps ink on a Material surface: a bare decorated container would lose
/// `ListTile`'s ink and trip Flutter's invisible-ink assertion.
class BrandCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const BrandCard({super.key, required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offset = BrandPalette.of(context).shadowOffset;
    final shadows = offset == Offset.zero
        ? const <BoxShadow>[]
        : <BoxShadow>[
            BoxShadow(color: scheme.shadow, offset: offset, blurRadius: 0),
          ];

    return Padding(
      // The shadow paints past the card's right and bottom edges. Reserving
      // that much room keeps it from clipping at a scroll view's edge.
      padding: EdgeInsets.only(right: offset.dx, bottom: offset.dy),
      child: Container(
        margin:
            margin ??
            const EdgeInsets.symmetric(
              vertical: BrandGeometry.cardMarginVertical,
            ),
        decoration: BoxDecoration(boxShadow: shadows),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BrandGeometry.corners,
            side: BorderSide(
              color: scheme.outline,
              width: BrandGeometry.borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
