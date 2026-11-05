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

  /// Pushes a page whose bar is [bar] over a first route, which is the only
  /// situation where Flutter offers an implied back arrow.
  ///
  /// The leading slots are pinned here because no page passes one; `actions` is
  /// pinned by the page tests instead.
  Future<void> pumpPushedBar(WidgetTester tester, PrimaryAppBar bar) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: lightTheme,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (context) => Scaffold(appBar: bar)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('draws and runs a custom leading control', (tester) async {
    var closeTapped = false;

    await pumpPushedBar(
      tester,
      PrimaryAppBar(
        title: 'Profile',
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => closeTapped = true,
        ),
      ),
    );

    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    expect(closeTapped, isTrue);
  });

  testWidgets('draws the implied back arrow by default', (tester) async {
    await pumpPushedBar(tester, const PrimaryAppBar(title: 'Profile'));

    expect(find.byType(BackButton), findsOneWidget);
  });

  // A new user must not be able to dismiss onboarding, so the bar has to be
  // able to suppress the arrow while supplying no leading of its own.
  testWidgets('draws no implied back arrow when told not to imply one', (
    tester,
  ) async {
    await pumpPushedBar(
      tester,
      const PrimaryAppBar(title: 'Profile', automaticallyImplyLeading: false),
    );

    expect(find.text('Profile'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });
}
