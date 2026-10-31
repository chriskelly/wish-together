import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';

const emptyMessage = 'nothing here';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget content({List<String>? items, Object? error}) =>
    ListContentBuilder<String>(
      items: items,
      error: error,
      entityWidgetBuilder: (_, item) => Text(item),
      emptyMessage: emptyMessage,
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
    await tester.pumpWidget(host(content(items: const ['one', 'two'])));

    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text(emptyMessage), findsNothing);
  });

  testWidgets('ListEmptyPlaceholder renders a 100px box with its message', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const ListEmptyPlaceholder(message: emptyMessage)),
    );

    expect(find.text(emptyMessage), findsOneWidget);
    expect(tester.getSize(find.byType(ListEmptyPlaceholder)).height, 100);
  });
}
