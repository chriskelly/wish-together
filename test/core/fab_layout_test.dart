import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/fab_layout.dart';

void main() {
  group('fabReserve', () {
    const fabHeight = 56.0;
    const defaultGap = 16.0;

    /// Reads the reserve under a MediaQuery with the given bottom view padding.
    Future<double> reserveFor(
      WidgetTester tester, {
      double bottomInset = 0,
      double? gap,
    }) async {
      late double reserve;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: Builder(
            builder: (context) {
              reserve = gap == null
                  ? fabReserve(context)
                  : fabReserve(context, gap: gap);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return reserve;
    }

    testWidgets('reserves the button height, its margin and the gap', (
      tester,
    ) async {
      final reserve = await reserveFor(tester);

      expect(reserve, fabHeight + kFloatingActionButtonMargin + defaultGap);
    });

    testWidgets('adds the device bottom inset below the safe-area edge', (
      tester,
    ) async {
      const bottomInset = 34.0;

      final reserve = await reserveFor(tester, bottomInset: bottomInset);

      expect(
        reserve,
        fabHeight + kFloatingActionButtonMargin + bottomInset + defaultGap,
      );
    });

    testWidgets('honours the gap a caller asks for', (tester) async {
      const gap = 24.0;

      final reserve = await reserveFor(tester, gap: gap);

      expect(reserve, fabHeight + kFloatingActionButtonMargin + gap);
    });
  });
}
