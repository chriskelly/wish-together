import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:wishtogether/core/design_tokens.dart';

/// A primary block holding a hero title and optional actions.
///
/// The title is laid out as explicit lines: the caller separates them with
/// `\n`, and each line is scaled down to the available width instead of being
/// soft-wrapped. A long name or a high text scale therefore shrinks the glyphs
/// rather than breaking a word and orphaning its last character. The trade-off
/// is deliberate: the hero's line never grows past the block, so a 2.0 text
/// scale is capped on this one control.
///
/// The title colour is always `colorScheme.onPrimary`, whatever colour the
/// supplied [titleStyle] carries. The actions sit on an `IconButtonTheme` with
/// the same foreground.
class BrandHero extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final TextStyle? titleStyle;

  const BrandHero({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = (titleStyle ?? theme.textTheme.displayMedium)?.copyWith(
      color: scheme.onPrimary,
    );
    final lines = title.split('\n');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The block paints under the status bar, so the icons must follow the
      // block's brightness rather than the platform's.
      value: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Container(
        width: double.infinity,
        color: scheme.primary,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BrandGeometry.spacingMd,
              BrandGeometry.spacingSm,
              BrandGeometry.spacingMd,
              BrandGeometry.spacingMd,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    label: title,
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in lines)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                line,
                                maxLines: 1,
                                softWrap: false,
                                style: style,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: BrandGeometry.spacingSm),
                  IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        foregroundColor: scheme.onPrimary,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
