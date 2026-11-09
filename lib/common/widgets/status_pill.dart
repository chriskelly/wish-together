import 'package:flutter/material.dart';

import 'package:wishtogether/core/design_tokens.dart';

/// The one vocabulary for claim state.
enum StatusPillTone { neutral, accent }

/// A claim-state badge.
///
/// `neutral` is outlined with muted ink and carries text the viewer does not
/// own ("Unavailable"). `accent` is a brass fill with `onSecondary` text ("you
/// claimed this"); brass never carries text on a light ground, so the fill is
/// the only way the colour is used here.
class StatusPill extends StatelessWidget {
  final String label;
  final StatusPillTone tone;

  const StatusPill({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = tone == StatusPillTone.accent;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandGeometry.spacingSm + 2,
        vertical: BrandGeometry.spacingXs,
      ),
      decoration: ShapeDecoration(
        color: accent ? scheme.secondary : null,
        shape: RoundedRectangleBorder(
          borderRadius: BrandGeometry.corners,
          side: accent
              ? BorderSide.none
              : BorderSide(
                  color: scheme.onSurfaceVariant,
                  width: BrandGeometry.borderWidth,
                ),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: accent ? scheme.onSecondary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
