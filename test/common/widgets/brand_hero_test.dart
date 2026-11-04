import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/brand_hero.dart';
import 'package:wishtogether/core/design_tokens.dart';
import 'package:wishtogether/core/theme.dart';

const firstLine = 'Welcome,';
const secondLine = 'Grace!';
const title = '$firstLine\n$secondLine';
const actionLabel = 'Profile';

Widget host({
  List<Widget> actions = const <Widget>[],
  String text = title,
  double textScale = 1.0,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? lightTheme,
  home: MediaQuery(
    // Inside MaterialApp, so it is not replaced by the view's own MediaQuery.
    data: MediaQueryData(
      size: const Size(320, 568),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: BrandHero(
        title: text,
        actions: actions,
        titleStyle: heroHomeTextStyle,
      ),
    ),
  ),
);

void main() {
  testWidgets('renders the title and its actions', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      host(
        actions: <Widget>[
          IconButton(
            onPressed: () => taps++,
            icon: const Icon(Icons.person_outline),
            tooltip: actionLabel,
          ),
        ],
      ),
    );

    expect(find.text(firstLine), findsOneWidget);
    expect(find.text(secondLine), findsOneWidget);

    await tester.tap(find.byTooltip(actionLabel));

    expect(taps, 1);
  });

  testWidgets('exposes the whole title as one heading', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(host());

    expect(find.bySemanticsLabel(title), findsOneWidget);
    handle.dispose();
  });

  testWidgets('status bar icons follow the block brightness', (tester) async {
    await tester.pumpWidget(host());

    AnnotatedRegion<SystemUiOverlayStyle> region() =>
        tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        );

    expect(region().value.statusBarIconBrightness, Brightness.light);

    await tester.pumpWidget(host(theme: darkTheme));
    // MaterialApp animates a theme change, so the first frame is still light.
    await tester.pumpAndSettle();

    expect(region().value.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('keeps explicit lines and never overflows at 320px, 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(textScale: 2.0));

    expect(find.text(firstLine), findsOneWidget);
    expect(find.text(secondLine), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scales an over-long line down instead of wrapping it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longLine = 'Alexandria-Cassandra Montgomery-Smythe';

    await tester.pumpWidget(host(text: longLine, textScale: 2.0));

    final fittedBox = find.ancestor(
      of: find.text(longLine),
      matching: find.byType(FittedBox),
    );
    final paintedWidth = tester.getSize(fittedBox).width;
    final naturalWidth = tester.getSize(find.text(longLine)).width;

    expect(
      naturalWidth,
      greaterThan(paintedWidth),
      reason: 'the line must be scaled down, not wrapped',
    );
    expect(paintedWidth, lessThanOrEqualTo(320 - 32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single-line title stays one line', (tester) async {
    await tester.pumpWidget(host(text: 'WishTogether'));

    expect(find.text('WishTogether'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
