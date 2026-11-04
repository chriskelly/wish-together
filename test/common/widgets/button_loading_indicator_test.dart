import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/core/theme.dart';

import '../../support/contrast_ratio.dart';

Widget host(ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    // Both call sites disable the button while the indicator is shown, so the
    // spinner sits on Material's disabled fill, not on the enabled one.
    body: ElevatedButton(
      onPressed: null,
      child: const ButtonLoadingIndicator(),
    ),
  ),
);

void main() {
  for (final theme in <ThemeData>[lightTheme, darkTheme]) {
    testWidgets(
      'stays visible on a disabled elevated button in ${theme.brightness.name}',
      (tester) async {
        await tester.pumpWidget(host(theme));

        final buttonMaterial = tester.widget<Material>(
          find
              .ancestor(
                of: find.byType(ButtonLoadingIndicator),
                matching: find.byType(Material),
              )
              .first,
        );
        final disabledFill = Color.alphaBlend(
          buttonMaterial.color!,
          theme.scaffoldBackgroundColor,
        );
        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );

        expect(
          contrastRatio(spinner.color!, disabledFill),
          greaterThanOrEqualTo(3.0),
          reason: 'the spinner is a graphic and needs 3:1 against its button',
        );
      },
    );
  }
}
