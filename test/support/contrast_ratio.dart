import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG relative-luminance contrast ratio.
double contrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}
