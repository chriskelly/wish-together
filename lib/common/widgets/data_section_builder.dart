import 'package:flutter/material.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';

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
              tooltip: 'Add new ${T.toString().toLowerCase()}',
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamListBuilder<T>(
          stream: stream,
          entityWidgetBuilder: entityWidgetBuilder,
          isScrollable: false,
          emptyWidget: Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                emptyListMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
