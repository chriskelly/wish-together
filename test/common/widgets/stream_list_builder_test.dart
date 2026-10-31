import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';

const emptyMessage = 'nothing here';
const firstItem = 'one';
const customEmpty = 'custom';
const listPadding = EdgeInsets.only(bottom: 48);

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget listBuilder(
  Stream<List<String>> stream, {
  Widget? emptyWidget,
  bool isScrollable = true,
  EdgeInsets? padding,
}) => StreamListBuilder<String>(
  stream: stream,
  entityWidgetBuilder: (_, item) => Text(item),
  emptyMessage: emptyMessage,
  emptyWidget: emptyWidget,
  isScrollable: isScrollable,
  listPadding: padding,
);

void main() {
  testWidgets('shows the spinner until the stream emits', (tester) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(host(listBuilder(controller.stream)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.add(const [firstItem]);
    await tester.pump();
    expect(find.text(firstItem), findsOneWidget);
  });

  testWidgets('shows the error text when the stream errors', (tester) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final error = Exception('offline');

    await tester.pumpWidget(host(listBuilder(controller.stream)));
    controller.addError(error);
    await tester.pump();

    expect(find.text('An error occurred: $error'), findsOneWidget);
  });

  testWidgets('shows the empty message for an empty list', (tester) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(host(listBuilder(controller.stream)));
    controller.add(const []);
    await tester.pump();

    expect(find.text(emptyMessage), findsOneWidget);
  });

  testWidgets('shows the empty message when a stream completes with no data', (
    tester,
  ) async {
    await tester.pumpWidget(host(listBuilder(Stream<List<String>>.empty())));
    await tester.pump();

    expect(find.text(emptyMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the empty widget in preference to the message', (
    tester,
  ) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(
      host(
        listBuilder(controller.stream, emptyWidget: const Text(customEmpty)),
      ),
    );
    controller.add(const []);
    await tester.pump();

    expect(find.text(customEmpty), findsOneWidget);
    expect(find.text(emptyMessage), findsNothing);
  });

  testWidgets('shows the spinner again when the stream identity changes', (
    tester,
  ) async {
    final first = StreamController<List<String>>.broadcast();
    final second = StreamController<List<String>>.broadcast();
    addTearDown(first.close);
    addTearDown(second.close);

    await tester.pumpWidget(host(listBuilder(first.stream)));
    first.add(const [firstItem]);
    await tester.pump();
    expect(find.text(firstItem), findsOneWidget);

    await tester.pumpWidget(host(listBuilder(second.stream)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(firstItem), findsNothing);
  });

  testWidgets(
    'shows the spinner, not a retained error, when the stream changes',
    (tester) async {
      final first = StreamController<List<String>>.broadcast();
      final second = StreamController<List<String>>.broadcast();
      addTearDown(first.close);
      addTearDown(second.close);
      final error = Exception('offline');

      await tester.pumpWidget(host(listBuilder(first.stream)));
      first.addError(error);
      await tester.pump();
      expect(find.text('An error occurred: $error'), findsOneWidget);

      await tester.pumpWidget(host(listBuilder(second.stream)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('An error occurred: $error'), findsNothing);
    },
  );

  testWidgets('forwards the list padding and the non-scrollable layout', (
    tester,
  ) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(
      host(
        listBuilder(
          controller.stream,
          isScrollable: false,
          padding: listPadding,
        ),
      ),
    );
    controller.add(const [firstItem]);
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.padding, listPadding);
    expect(listView.shrinkWrap, isTrue);
  });
}
