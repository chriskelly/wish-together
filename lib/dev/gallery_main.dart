import 'package:flutter/material.dart';

import 'package:wishtogether/dev/dev_notice_screen.dart';
import 'package:wishtogether/dev/theme_gallery.dart';

/// Entrypoint for the committed theme gallery:
/// `tool/dev.sh --entrypoint lib/dev/gallery_main.dart`.
///
/// Nothing under `lib/main.dart` imports this file, so it is absent from the
/// production bundle.
void main() => runApp(buildDevPageApp(const ThemeGallery()));
