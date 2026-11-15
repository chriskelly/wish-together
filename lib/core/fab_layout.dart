import 'package:flutter/material.dart';
import 'package:wishtogether/core/design_tokens.dart';

/// Bottom space a page reserves so its last row clears a floating action
/// button: the button's height (56 at the Material 3 defaults, and text
/// scaling does not change it), the margin between it and the safe-area edge,
/// the device's bottom inset below that edge, and [gap] between the row and the
/// button.
///
/// Covers the default 56 px button and the extended variant; a mini or large
/// button needs its own height.
///
/// The formula assumes a floating (end or center float) button over a body that
/// runs to the view bottom, with no persistent bottom sheet. A docked or
/// contained button, or a bottom bar that shortens the body, lifts less than
/// this; a bottom sheet lifts more and needs its own allowance.
double fabReserve(
  BuildContext context, {
  double gap = BrandGeometry.spacingMd,
}) =>
    56 +
    kFloatingActionButtonMargin +
    MediaQuery.viewPaddingOf(context).bottom +
    gap;
