import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/theme.dart';

void main() {
  testWidgets('paints the 2px rule at the bottom of the bar', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: lightTheme,
          home: const Scaffold(appBar: PrimaryAppBar(title: 'My Wishlists')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late ByteData bytes;
    late int width;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      width = image.width;
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    void expectPixel(int x, int y, Color expected) {
      final offset = (y * width + x) * 4;
      expect(
        bytes.getUint8(offset),
        closeTo((expected.r * 255).round(), 2),
        reason: 'red at $x,$y',
      );
      expect(
        bytes.getUint8(offset + 1),
        closeTo((expected.g * 255).round(), 2),
        reason: 'green at $x,$y',
      );
      expect(
        bytes.getUint8(offset + 2),
        closeTo((expected.b * 255).round(), 2),
        reason: 'blue at $x,$y',
      );
    }

    // The bar is 56 logical pixels tall; the rule occupies its last two rows.
    expectPixel(10, 20, lightTheme.scaffoldBackgroundColor);
    expectPixel(10, 54, lightTheme.colorScheme.outline);
    expectPixel(10, 55, lightTheme.colorScheme.outline);
  });
}
