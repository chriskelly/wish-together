import 'package:flutter/material.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';

/// A titled section with an add action and one child.
///
/// `DataSectionBuilder` pairs it with `StreamListBuilder`; a page that holds its
/// own state pairs it with `ListContentBuilder`.
class DataSection extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;

  /// The add button's tooltip. Passed in rather than derived from a type
  /// argument, so this widget stays non-generic and each call site decides the
  /// exact string its users see.
  final String addTooltip;
  final Widget child;

  const DataSection({
    super.key,
    required this.title,
    required this.onAdd,
    required this.addTooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onAdd,
              tooltip: addTooltip,
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class DataSectionBuilder<T> extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;
  final Stream<List<T>> stream;
  final String emptyListMessage;
  final EntityWidgetBuilder<T> entityWidgetBuilder;

  const DataSectionBuilder({
    super.key,
    required this.title,
    required this.onAdd,
    required this.stream,
    required this.emptyListMessage,
    required this.entityWidgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return DataSection(
      title: title,
      onAdd: onAdd,
      addTooltip: 'Add new ${T.toString().toLowerCase()}',
      child: StreamListBuilder<T>(
        stream: stream,
        entityWidgetBuilder: entityWidgetBuilder,
        isScrollable: false,
        emptyWidget: ListEmptyPlaceholder(message: emptyListMessage),
      ),
    );
  }
}
