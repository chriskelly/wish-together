import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';

const emptyMessage = 'nothing here';
const firstItem = 'one';
const secondItem = 'two';
const customLoading = 'custom loading';
const customError = 'custom error';
const placeholderHeight = 100.0;

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget content({
  List<String>? items,
  Object? error,
  Widget? loadingWidget,
  Widget? errorWidget,
}) => ListContentBuilder<String>(
  items: items,
  error: error,
  entityWidgetBuilder: (_, item) => Text(item),
  emptyMessage: emptyMessage,
  loadingWidget: loadingWidget,
  errorWidget: errorWidget,
);

void main() {
  testWidgets('shows the spinner while items are null and no error is set', (
    tester,
  ) async {
    await tester.pumpWidget(host(content()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error text for an error with no items', (
    tester,
  ) async {
    final error = Exception('offline');

    await tester.pumpWidget(host(content(error: error)));

    expect(find.text('An error occurred: $error'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the empty message for an empty list', (tester) async {
    await tester.pumpWidget(host(content(items: const [])));

    expect(find.text(emptyMessage), findsOneWidget);
  });

  testWidgets('shows one widget per item', (tester) async {
    await tester.pumpWidget(
      host(content(items: const [firstItem, secondItem])),
    );

    expect(find.text(firstItem), findsOneWidget);
    expect(find.text(secondItem), findsOneWidget);
    expect(find.text(emptyMessage), findsNothing);
  });

  testWidgets('prefers the custom loading widget', (tester) async {
    await tester.pumpWidget(
      host(content(loadingWidget: const Text(customLoading))),
    );

    expect(find.text(customLoading), findsOneWidget);
  });

  testWidgets('prefers the custom error widget', (tester) async {
    await tester.pumpWidget(
      host(
        content(
          error: Exception('offline'),
          errorWidget: const Text(customError),
        ),
      ),
    );

    expect(find.text(customError), findsOneWidget);
  });

  testWidgets(
    'ListEmptyPlaceholder renders a fixed-height box with its message',
    (tester) async {
      await tester.pumpWidget(
        host(const ListEmptyPlaceholder(message: emptyMessage)),
      );

      expect(find.text(emptyMessage), findsOneWidget);
      expect(
        tester.getSize(find.byType(ListEmptyPlaceholder)).height,
        placeholderHeight,
      );
    },
  );

  testWidgets('a nested list does not add the safe-area padding twice', (
    tester,
  ) async {
    const header = 'My Wishlists';
    const itemHeight = 20.0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 59, bottom: 34),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(header),
                  ListContentBuilder<String>(
                    items: const [firstItem, secondItem],
                    isScrollable: false,
                    entityWidgetBuilder: (_, item) =>
                        SizedBox(height: itemHeight, child: Text(item)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final headerBottom = tester.getBottomLeft(find.text(header)).dy;
    final firstTop = tester.getTopLeft(find.text(firstItem)).dy;
    final lastBottom = tester.getBottomLeft(find.text(secondItem)).dy;
    final listBottom = tester
        .getBottomLeft(find.byType(ListContentBuilder<String>))
        .dy;

    expect(
      firstTop - headerBottom,
      lessThan(1.0),
      reason: 'the outer scroll view already owns the safe area',
    );
    expect(listBottom - lastBottom, lessThan(1.0));
  });
}
