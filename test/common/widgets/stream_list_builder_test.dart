import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';

const emptyMessage = 'nothing here';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget listBuilder(Stream<List<String>> stream, {Widget? emptyWidget}) =>
    StreamListBuilder<String>(
      stream: stream,
      entityWidgetBuilder: (_, item) => Text(item),
      emptyMessage: emptyMessage,
      emptyWidget: emptyWidget,
    );

void main() {
  testWidgets('shows the spinner until the stream emits', (tester) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(host(listBuilder(controller.stream)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.add(const ['one']);
    await tester.pump();
    expect(find.text('one'), findsOneWidget);
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
      host(listBuilder(controller.stream, emptyWidget: const Text('custom'))),
    );
    controller.add(const []);
    await tester.pump();

    expect(find.text('custom'), findsOneWidget);
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
    first.add(const ['one']);
    await tester.pump();
    expect(find.text('one'), findsOneWidget);

    await tester.pumpWidget(host(listBuilder(second.stream)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('one'), findsNothing);
  });
}
