import 'package:flutter/material.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/core/design_tokens.dart';

/// A titled section with an add action and one child.
///
/// A page whose providers own the reads pairs it with `ListContentBuilder`.
/// `DataSectionBuilder` and `StreamListBuilder` are retired; nothing in `lib/`
/// uses them any more.
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The display face and its tracking come from the type scale.
            Text(title, style: theme.textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: theme.colorScheme.primary,
              onPressed: onAdd,
              tooltip: addTooltip,
            ),
          ],
        ),
        const SizedBox(height: BrandGeometry.spacingSm),
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
