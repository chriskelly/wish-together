import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/data_section_builder.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';

const title = 'My Things';
const emptyListMessage = 'No things yet.';
const addTooltip = 'Add new string';
const firstItem = 'one';
const placeholderHeight = 100.0;

Widget section(Stream<List<String>> stream, {VoidCallback? onAdd}) =>
    MaterialApp(
      home: Scaffold(
        body: DataSectionBuilder<String>(
          title: title,
          onAdd: onAdd ?? () {},
          stream: stream,
          emptyListMessage: emptyListMessage,
          entityWidgetBuilder: (_, item) => Text(item),
        ),
      ),
    );

void main() {
  testWidgets('renders the title, the add action and the items', (
    tester,
  ) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    var adds = 0;

    await tester.pumpWidget(section(controller.stream, onAdd: () => adds++));
    expect(find.text(title), findsOneWidget);

    controller.add(const [firstItem]);
    await tester.pump();
    expect(find.text(firstItem), findsOneWidget);

    await tester.tap(find.byTooltip(addTooltip));
    expect(adds, 1);
  });

  testWidgets('shows the bordered empty placeholder for an empty list', (
    tester,
  ) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(section(controller.stream));
    controller.add(const []);
    await tester.pump();

    expect(find.text(emptyListMessage), findsOneWidget);
    expect(
      tester.getSize(find.byType(ListEmptyPlaceholder)).height,
      placeholderHeight,
    );
  });
}
